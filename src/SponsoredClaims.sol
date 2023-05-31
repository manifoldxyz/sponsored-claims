// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1155Creator} from "./creator/ERC1155Creator.sol";
import {ERC721Creator} from "./creator/ERC721Creator.sol";
import {Create2} from "openzeppelin/utils/Create2.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Address} from "openzeppelin/utils/Address.sol";
import {IERC1155LazyPayableClaim} from
    "creator-core-extensions-solidity/manifold/lazyclaim/IERC1155LazyPayableClaim.sol";
import {IERC721LazyPayableClaim} from "creator-core-extensions-solidity/manifold/lazyclaim/IERC721LazyPayableClaim.sol";
import {Recipient, RoyaltySplitter} from "./splitter/RoyaltySplitter.sol";
import {ISponsoredClaims} from "./ISponsoredClaims.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";

interface ICreatorCore {
    function registerExtension(address extension, string calldata baseURI) external;
    function getExtensions() external view returns (address[] memory);
}

contract SponsoredClaims is ISponsoredClaims, Ownable {
    uint16 public constant MAX_FEE = 10000; // 100%

    address public erc721ClaimExtension;
    address public erc1155ClaimExtension;

    mapping(address => address) public contractCreators;

    address public signer;

    constructor(address erc721ClaimExtension_, address erc1155ClaimExtension_, address signer_) {
        erc721ClaimExtension = erc721ClaimExtension_;
        erc1155ClaimExtension = erc1155ClaimExtension_;
        signer = signer_;
    }

    /**
     * @dev Sponsorship logic
     */

    function sponsorERC721Claim(
        ContractMetadata memory contractMetadata,
        ERC721SponsoredClaimParameters memory sponsoredClaimParameters,
        bytes memory signature
    ) external returns (address) {
        _verifyParameters(contractMetadata, sponsoredClaimParameters.sponsorFee, Spec.ERC721);

        // 1. Verify signature is valid allowing this msg.sender to sponsor the claim
        if (ECDSA.recover(_formatMessage(contractMetadata, abi.encode(sponsoredClaimParameters)), signature) != signer)
        {
            revert Unauthorized();
        }

        // 2. Create contract if it doesn't exist and register extension
        address creatorContractAddress = _initializeContract(contractMetadata);

        // 3. Deploy royalty splitter if not provided
        if (sponsoredClaimParameters.claimParameters.paymentReceiver == address(0)) {
            sponsoredClaimParameters.claimParameters.paymentReceiver =
                _deployRoyaltySplitter(creatorContractAddress, msg.sender, sponsoredClaimParameters.sponsorFee);
        }

        // 4. Initialize claim with the extension
        IERC721LazyPayableClaim(erc721ClaimExtension).initializeClaim(
            creatorContractAddress, sponsoredClaimParameters.instanceId, sponsoredClaimParameters.claimParameters
        );

        return creatorContractAddress;
    }

    function sponsorERC1155Claim(
        ContractMetadata memory contractMetadata,
        ERC1155SponsoredClaimParameters memory sponsoredClaimParameters,
        bytes memory signature
    ) external returns (address) {
        _verifyParameters(contractMetadata, sponsoredClaimParameters.sponsorFee, Spec.ERC1155);

        // 1. Verify signature is valid allowing this msg.sender to sponsor the claim
        if (ECDSA.recover(_formatMessage(contractMetadata, abi.encode(sponsoredClaimParameters)), signature) != signer)
        {
            revert Unauthorized();
        }

        // 2. Create contract if it doesn't exist and register extension
        address creatorContractAddress = _initializeContract(contractMetadata);

        // 3. Deploy royalty splitter if not provided
        if (sponsoredClaimParameters.claimParameters.paymentReceiver == address(0)) {
            sponsoredClaimParameters.claimParameters.paymentReceiver =
                _deployRoyaltySplitter(creatorContractAddress, msg.sender, sponsoredClaimParameters.sponsorFee);
        }

        // 4. Initialize claim with the extension
        IERC1155LazyPayableClaim(erc1155ClaimExtension).initializeClaim(
            creatorContractAddress, sponsoredClaimParameters.instanceId, sponsoredClaimParameters.claimParameters
        );

        return creatorContractAddress;
    }

    function _verifyParameters(ContractMetadata memory contractMetadata, uint16 sponsorFee, Spec expectedSpec)
        internal
        view
    {
        if (msg.sender == contractMetadata.creator) {
            revert OwnerCannotSponsor();
        }
        if (contractMetadata.spec != expectedSpec) {
            revert IncorrectSpec();
        }
        if (sponsorFee > MAX_FEE) {
            revert IncorrectFee();
        }
    }

    function _deployRoyaltySplitter(address creatorContractAddress, address sponsor, uint16 sponsorFee)
        internal
        returns (address payable)
    {
        Recipient[] memory recipients = new Recipient[](2);
        recipients[0] = Recipient({recipient: payable(sponsor), bps: sponsorFee});
        recipients[1] =
            Recipient({recipient: payable(contractCreators[creatorContractAddress]), bps: MAX_FEE - sponsorFee});

        // TODO: Properly set up a minimal royalty splitter contract using proxies
        // Quickly added this for proof-of-concept purposes
        return payable(address(new RoyaltySplitter(recipients)));
    }

    function onERC1155Received(address, address, uint256, uint256 value, bytes memory) public pure returns (bytes4) {
        // only allow initializations
        if (value == 0) {
            return 0xf23a6e61;
        } else {
            return 0x0;
        }
    }

    /**
     * @dev Contract creation logic
     */

    function createContract(ContractMetadata memory contractMetadata) public returns (address) {
        bytes memory code = _code(contractMetadata);
        bytes32 salt = _salt(contractMetadata.creator);
        address creatorContractAddress = Create2.computeAddress(salt, keccak256(code));

        if (!Address.isContract(creatorContractAddress)) {
            creatorContractAddress = Create2.deploy(0, salt, code);
        }

        if (contractMetadata.creator == msg.sender && Ownable(creatorContractAddress).owner() != msg.sender) {
            Ownable(creatorContractAddress).transferOwnership(msg.sender);
        }

        contractCreators[creatorContractAddress] = payable(contractMetadata.creator);

        return creatorContractAddress;
    }

    function contractAddress(ContractMetadata memory contractMetadata) public view returns (address) {
        return Create2.computeAddress(_salt(contractMetadata.creator), keccak256(_code(contractMetadata)));
    }

    function _code(ContractMetadata memory contractMetadata) internal pure returns (bytes memory) {
        bytes memory creationCode =
            contractMetadata.spec == Spec.ERC1155 ? type(ERC1155Creator).creationCode : type(ERC721Creator).creationCode;
        return abi.encodePacked(creationCode, abi.encode(contractMetadata.name, contractMetadata.symbol));
    }

    function _salt(address creator) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(address(creator))));
    }

    function _initializeContract(ContractMetadata memory contractMetadata) internal returns (address) {
        address creatorContractAddress = createContract(contractMetadata);
        address extension = contractMetadata.spec == Spec.ERC721 ? erc721ClaimExtension : erc1155ClaimExtension;

        // Validate extension isn't already registered
        address[] memory extensions = ICreatorCore(creatorContractAddress).getExtensions();
        for (uint256 i = 0; i < extensions.length; i++) {
            if (extensions[i] == extension) {
                return creatorContractAddress;
            }
        }

        ICreatorCore(creatorContractAddress).registerExtension(extension, "");

        return creatorContractAddress;
    }

    /**
     * @dev Validation logic
     */

    function _formatMessage(ContractMetadata memory contractMetadata, bytes memory sponsoredClaimParameters)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n84", abi.encode(contractMetadata), sponsoredClaimParameters)
        );
    }

    /**
     * @dev Admin logic
     */

    function updateSigner(address newSigner) public onlyOwner {
        signer = newSigner;
    }

    function updateERC721ClaimExtension(address newERC721ClaimExtension) external onlyOwner {
        erc721ClaimExtension = newERC721ClaimExtension;
    }

    function updateERC1155ClaimExtension(address newERC1155ClaimExtension) external onlyOwner {
        erc1155ClaimExtension = newERC1155ClaimExtension;
    }
}
