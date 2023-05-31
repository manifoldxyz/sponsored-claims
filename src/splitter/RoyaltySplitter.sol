// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.0;

/**
 * Taken from https://github.com/manifoldxyz/royalty-registry-solidity/blob/main/contracts/overrides/RoyaltySplitter.sol
 * TODO: Use Clones factory, slightly modified to simplify for now
 */

import "openzeppelin/proxy/utils/Initializable.sol";
import "openzeppelin/utils/Address.sol";
import "openzeppelin/utils/introspection/ERC165.sol";
import "openzeppelin/utils/introspection/IERC165.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/proxy/Clones.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "./BytesLibrary.sol";

struct Recipient {
    address payable recipient;
    uint16 bps;
}

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
    function increaseAllowance(address spender, uint256 amount) external returns (bool);
}

interface IRoyaltySplitter is IERC165 {
    /**
     * @dev Get the splitter recipients;
     */
    function getRecipients() external view returns (Recipient[] memory);
}

/**
 * Cloneable and configurable royalty splitter contract
 */
contract RoyaltySplitter is Initializable, ERC165 {
    using BytesLibrary for bytes;
    using Address for address payable;
    using Address for address;
    using SafeMath for uint256;

    uint256 internal constant BASIS_POINTS = 10000;
    uint256 constant IERC20_APPROVE_SELECTOR = 0x095ea7b300000000000000000000000000000000000000000000000000000000;
    uint256 constant SELECTOR_MASK = 0xffffffff00000000000000000000000000000000000000000000000000000000;

    Recipient[] private _recipients;

    event PercentSplitCreated(address indexed contractAddress);
    event PercentSplitShare(address indexed recipient, uint256 percentInBasisPoints);
    event ETHTransferred(address indexed account, uint256 amount);
    event ERC20Transferred(address indexed erc20Contract, address indexed account, uint256 amount);

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IRoyaltySplitter).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Requires that the msg.sender is one of the recipients in this split.
     */
    modifier onlyRecipient() {
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i].recipient == msg.sender) {
                _;
                return;
            }
        }
        revert("Split: Can only be called by one of the recipients");
    }

    constructor(Recipient[] memory recipients) {
        _setRecipients(recipients);
    }

    function _setRecipients(Recipient[] memory recipients) private {
        delete _recipients;
        if (recipients.length == 0) {
            return;
        }
        uint256 totalBPS;
        for (uint256 i; i < recipients.length; ++i) {
            totalBPS += recipients[i].bps;
            _recipients.push(recipients[i]);
        }
        require(totalBPS == BASIS_POINTS, "Total bps must be 10000");
    }

    /**
     * @dev Get the splitter recipients;
     */
    function getRecipients() external view returns (Recipient[] memory) {
        return _recipients;
    }

    /**
     * @notice Forwards any ETH received to the recipients in this split.
     * @dev Each recipient increases the gas required to split
     * and contract recipients may significantly increase the gas required.
     */
    receive() external payable {
        _splitETH(msg.value);
    }

    /**
     * @notice Allows any ETH stored by the contract to be split among recipients.
     * @dev Normally ETH is forwarded as it comes in, but a balance in this contract
     * is possible if it was sent before the contract was created or if self destruct was used.
     */
    function splitETH() public {
        _splitETH(address(this).balance);
    }

    function _splitETH(uint256 value) internal {
        if (value > 0) {
            uint256 totalSent;
            uint256 amountToSend;
            unchecked {
                for (uint256 i = _recipients.length - 1; i > 0; i--) {
                    Recipient memory recipient = _recipients[i];
                    amountToSend = (value * recipient.bps) / BASIS_POINTS;
                    totalSent += amountToSend;
                    recipient.recipient.sendValue(amountToSend);
                    emit ETHTransferred(recipient.recipient, amountToSend);
                }
                // Favor the 1st recipient if there are any rounding issues
                amountToSend = value - totalSent;
            }
            _recipients[0].recipient.sendValue(amountToSend);
            emit ETHTransferred(_recipients[0].recipient, amountToSend);
        }
    }

    /**
     * @notice Anyone can call this function to split all available tokens at the provided address between the recipients.
     * @dev This contract is built to split ETH payments. The ability to attempt to split ERC20 tokens is here
     * just in case tokens were also sent so that they don't get locked forever in the contract.
     */
    function splitERC20Tokens(IERC20 erc20Contract) public {
        require(_splitERC20Tokens(erc20Contract), "Split: ERC20 split failed");
    }

    function _splitERC20Tokens(IERC20 erc20Contract) internal returns (bool) {
        try erc20Contract.balanceOf(address(this)) returns (uint256 balance) {
            if (balance == 0) {
                return false;
            }
            uint256 amountToSend;
            uint256 totalSent;
            unchecked {
                for (uint256 i = _recipients.length - 1; i > 0; i--) {
                    Recipient memory recipient = _recipients[i];
                    bool success;
                    (success, amountToSend) = balance.tryMul(recipient.bps);

                    amountToSend /= BASIS_POINTS;
                    totalSent += amountToSend;
                    try erc20Contract.transfer(recipient.recipient, amountToSend) {
                        emit ERC20Transferred(address(erc20Contract), recipient.recipient, amountToSend);
                    } catch {
                        return false;
                    }
                }
                // Favor the 1st recipient if there are any rounding issues
                amountToSend = balance - totalSent;
            }
            try erc20Contract.transfer(_recipients[0].recipient, amountToSend) {
                emit ERC20Transferred(address(erc20Contract), _recipients[0].recipient, amountToSend);
            } catch {
                return false;
            }
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Allows the split recipients to make an arbitrary contract call.
     * @dev This is provided to allow recovering from unexpected scenarios,
     * such as receiving an NFT at this address.
     *
     * It will first attempt a fair split of ERC20 tokens before proceeding.
     *
     * This contract is built to split ETH payments. The ability to attempt to make other calls is here
     * just in case other assets were also sent so that they don't get locked forever in the contract.
     */
    function proxyCall(address payable target, bytes calldata callData) external onlyRecipient {
        require(
            !callData.startsWith(IERC20Approve.approve.selector)
                && !callData.startsWith(IERC20Approve.increaseAllowance.selector),
            "Split: ERC20 tokens must be split"
        );
        try this.splitERC20Tokens(IERC20(target)) {} catch {}
        target.functionCall(callData);
    }
}
