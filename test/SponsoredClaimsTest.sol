// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SponsoredClaims} from "../src/SponsoredClaims.sol";
import {ISponsoredClaims} from "../src/ISponsoredClaims.sol";
import {IERC721LazyPayableClaim} from "creator-core-extensions-solidity/manifold/lazyclaim/IERC721LazyPayableClaim.sol";
import {IERC1155LazyPayableClaim} from
    "creator-core-extensions-solidity/manifold/lazyclaim/IERC1155LazyPayableClaim.sol";
import {ILazyPayableClaim} from "creator-core-extensions-solidity/manifold/lazyclaim/ILazyPayableClaim.sol";
import {Recipient, RoyaltySplitter} from "../src/splitter/RoyaltySplitter.sol";

interface IOwnable {
    function owner() external view returns (address);
}

interface IToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function balanceOf(address _owner, uint256 _id) external view returns (uint256);
    function ownerOf(uint256 _id) external view returns (address);
}

contract SponsoredClaimsTest is Test {
    IERC721LazyPayableClaim public erc721ClaimExtension;
    IERC1155LazyPayableClaim public erc1155ClaimExtension;
    SponsoredClaims public factory;

    address public creator = address(0xa11ce);
    address public sponsor = address(0xb0b);
    address public user = address(0xca1);

    address internal _signer;
    uint256 internal _signerPrivateKey;

    uint256 public constant MINT_FEE = 500000000000000;

    function setUp() public {
        // Forking Goerli because I'm having trouble importing creator-core-solidity
        vm.createSelectFork("https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161");

        // Set up signer
        _signerPrivateKey = 0x1337;
        _signer = vm.addr(_signerPrivateKey);

        // Set up contracts
        erc721ClaimExtension = IERC721LazyPayableClaim(0x074EAee8fC3E4e2b361762253F83d9a94aEC6fD4);
        erc1155ClaimExtension = IERC1155LazyPayableClaim(0x73CA7420625d312d1792Cea60Ced7B35D009322c);
        factory = new SponsoredClaims(address(erc721ClaimExtension), address(erc1155ClaimExtension), _signer);

        // Reset balances to 0
        vm.deal(creator, 0);
        vm.deal(sponsor, 0);
        vm.deal(user, 0);
    }

    function testSponsorERC721Claim() public {
        // 1. Set up claim via sponsor
        vm.startPrank(sponsor);

        ISponsoredClaims.ContractMetadata memory contractMetadata = _contractMetadata(ISponsoredClaims.Spec.ERC721);

        ISponsoredClaims.ERC721SponsoredClaimParameters memory sponsoredClaimParameters = ISponsoredClaims
            .ERC721SponsoredClaimParameters({
            instanceId: 1,
            claimParameters: IERC721LazyPayableClaim.ClaimParameters({
                merkleRoot: "",
                location: "XXX",
                totalMax: 10,
                walletMax: 1,
                startDate: 0,
                endDate: 0,
                storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
                cost: 1000000000000000,
                paymentReceiver: payable(address(0)),
                erc20: address(0),
                identical: true
            }),
            sponsorFee: 2500 // 25%
        });

        bytes memory signature = _sign(contractMetadata, abi.encode(sponsoredClaimParameters));

        address creatorContractAddress =
            factory.sponsorERC721Claim(contractMetadata, sponsoredClaimParameters, signature);

        vm.stopPrank();

        // 2. Mint by external user
        _mint(
            address(erc721ClaimExtension),
            creatorContractAddress,
            sponsoredClaimParameters.instanceId,
            sponsoredClaimParameters.claimParameters.cost
        );

        // 3. Distribute earnings
        address paymentReceiver =
            erc721ClaimExtension.getClaim(creatorContractAddress, sponsoredClaimParameters.instanceId).paymentReceiver;
        RoyaltySplitter(payable(paymentReceiver)).splitETH();

        // 4. Verify balances
        assertEq(IToken(creatorContractAddress).ownerOf(1), user);
        assertEq(user.balance, 0);
        assertEq(creator.balance, 750000000000000);
        assertEq(sponsor.balance, 250000000000000);
    }

    function testSponsorERC1155Claim() public {
        // 1. Set up claim via sponsor
        vm.startPrank(sponsor);

        ISponsoredClaims.ContractMetadata memory contractMetadata = _contractMetadata(ISponsoredClaims.Spec.ERC1155);

        ISponsoredClaims.ERC1155SponsoredClaimParameters memory sponsoredClaimParameters = ISponsoredClaims
            .ERC1155SponsoredClaimParameters({
            instanceId: 1,
            claimParameters: IERC1155LazyPayableClaim.ClaimParameters({
                merkleRoot: "",
                location: "XXX",
                totalMax: 10,
                walletMax: 1,
                startDate: 0,
                endDate: 0,
                storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
                cost: 1000000000000000,
                paymentReceiver: payable(address(0)),
                erc20: address(0)
            }),
            sponsorFee: 2500 // 25%
        });

        bytes memory signature = _sign(contractMetadata, abi.encode(sponsoredClaimParameters));

        address creatorContractAddress =
            factory.sponsorERC1155Claim(contractMetadata, sponsoredClaimParameters, signature);

        vm.stopPrank();

        // 2. Mint by external user
        _mint(
            address(erc1155ClaimExtension),
            creatorContractAddress,
            sponsoredClaimParameters.instanceId,
            sponsoredClaimParameters.claimParameters.cost
        );

        // 3. Distribute earnings
        address paymentReceiver =
            erc1155ClaimExtension.getClaim(creatorContractAddress, sponsoredClaimParameters.instanceId).paymentReceiver;
        RoyaltySplitter(payable(paymentReceiver)).splitETH();

        // 4. Verify balances
        uint256 tokenId =
            erc1155ClaimExtension.getClaim(creatorContractAddress, sponsoredClaimParameters.instanceId).tokenId;
        assertEq(IToken(creatorContractAddress).balanceOf(user, tokenId), 1);
        assertEq(user.balance, 0);
        assertEq(creator.balance, 750000000000000);
        assertEq(sponsor.balance, 250000000000000);
    }

    /**
     * @dev Ownership transfer trests
     */

    function testOwnershipTransferredOnCreation() public {
        vm.startPrank(creator);
        address creatorContractAddress = _createContract(_contractMetadata(ISponsoredClaims.Spec.ERC1155));
        // Verify ownership is transferred to msg.sender (creator) on creation
        assertEq(IOwnable(creatorContractAddress).owner(), creator);
    }

    function testOwnershipNotTransferredOnCreation() public {
        address creatorContractAddress = _createContract(_contractMetadata(ISponsoredClaims.Spec.ERC1155));
        // Verify ownership stays as the factory on creation if msg.sender != owner
        assertEq(IOwnable(creatorContractAddress).owner(), address(factory));
    }

    /**
     * @dev Utilities
     */

    function _contractMetadata(ISponsoredClaims.Spec spec)
        internal
        view
        returns (ISponsoredClaims.ContractMetadata memory)
    {
        return ISponsoredClaims.ContractMetadata({name: "Test", symbol: "TEST", creator: creator, spec: spec});
    }

    function _createContract(ISponsoredClaims.ContractMetadata memory contractMetadata) internal returns (address) {
        address creatorContractAddress = factory.createContract(contractMetadata);
        assertEq(IToken(creatorContractAddress).name(), "Test");
        assertEq(IToken(creatorContractAddress).symbol(), "TEST");
        assertEq(creatorContractAddress, factory.contractAddress(contractMetadata));
        return creatorContractAddress;
    }

    function _sign(SponsoredClaims.ContractMetadata memory contractMetadata, bytes memory sponsoredClaimParameters)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _signerPrivateKey,
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n84", abi.encode(contractMetadata), sponsoredClaimParameters
                )
            )
        );
        return abi.encodePacked(r, s, v);
    }

    function _mint(address claimExtension, address creatorContractAddress, uint256 instanceId, uint256 mintPrice)
        internal
    {
        vm.startPrank(user);
        uint256 mintCost = mintPrice + MINT_FEE;
        vm.deal(user, mintCost);
        bytes32[] memory merkleProof;
        ILazyPayableClaim(address(claimExtension)).mint{value: mintCost}(
            creatorContractAddress, instanceId, 0, merkleProof, user
        );
        vm.stopPrank();
    }
}
