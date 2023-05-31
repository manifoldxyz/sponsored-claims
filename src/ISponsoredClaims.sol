// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC1155LazyPayableClaim} from
    "creator-core-extensions-solidity/manifold/lazyclaim/IERC1155LazyPayableClaim.sol";
import {IERC721LazyPayableClaim} from "creator-core-extensions-solidity/manifold/lazyclaim/IERC721LazyPayableClaim.sol";

interface ISponsoredClaims {
    error OwnerCannotSponsor();
    error Unauthorized();
    error IncorrectSpec();
    error IncorrectFee();

    enum Spec {
        ERC1155,
        ERC721
    }

    struct ContractMetadata {
        string name;
        string symbol;
        address creator;
        Spec spec;
    }

    struct ERC1155SponsoredClaimParameters {
        uint256 instanceId;
        IERC1155LazyPayableClaim.ClaimParameters claimParameters;
        uint16 sponsorFee;
    }

    struct ERC721SponsoredClaimParameters {
        uint256 instanceId;
        IERC721LazyPayableClaim.ClaimParameters claimParameters;
        uint16 sponsorFee;
    }

    /**
     * @notice Sponsor an ERC721 claim on behalf of a creator.
     * @dev This function will create the contract if it doesn't exist, and register the ERC721 Claim Extension
     * @param contractMetadata the metadata used to identify the contract
     * @param sponsoredClaimParameters the parameters used to create the sponsored claim
     * @param signature the signature approving the sponsor to create the claim
     */
    function sponsorERC721Claim(
        ContractMetadata memory contractMetadata,
        ERC721SponsoredClaimParameters memory sponsoredClaimParameters,
        bytes memory signature
    ) external returns (address);

    /**
     * @notice Sponsor an ERC1155 claim on behalf of a creator.
     * @dev This function will create the contract if it doesn't exist, and register the ERC1155 Claim Extension
     * @param contractMetadata the metadata used to identify the contract
     * @param sponsoredClaimParameters the parameters used to create the sponsored claim
     * @param signature the signature approving the sponsor to create the claim
     */
    function sponsorERC1155Claim(
        ContractMetadata memory contractMetadata,
        ERC1155SponsoredClaimParameters memory sponsoredClaimParameters,
        bytes memory signature
    ) external returns (address);

    /**
     * @notice Create a creator contract at the deterministic address specified by `contractAddress(ContractMetadata)` call
     * @dev This contract can be created by any Ethereum user, however only the creator specified in the ContractMetadata
     * can claim ownership. Until then, the factory is the de-facto owner.
     * @param contractMetadata the metadata used to create the contract
     * @return the address of the created contract
     */
    function createContract(ContractMetadata memory contractMetadata) external returns (address);

    /**
     * @notice Generate a determinstic contract address using the ContractMetadata parameters.
     * @dev This is the address that the creator contract will be deployed to if `createContract(ContractMetadata)` is called.
     * @param contractMetadata the metadata used to generate the contract address
     * @return the address of the contract
     */
    function contractAddress(ContractMetadata memory contractMetadata) external view returns (address);

    /**
     * @notice Update the signer used to verify messages.
     * @param newSigner the address of the new signer
     */
    function updateSigner(address newSigner) external;

    /**
     * @notice Update the ERC721 Claim Extension to the specified address.
     * @param newERC721ClaimExtension the address of the new ERC721 Claim Extension
     */
    function updateERC721ClaimExtension(address newERC721ClaimExtension) external;

    /**
     * @notice Update the ERC1155 Claim Extension to the specified address.
     * @param newERC1155ClaimExtension the address of the new ERC1155 Claim Extension
     */
    function updateERC1155ClaimExtension(address newERC1155ClaimExtension) external;
}
