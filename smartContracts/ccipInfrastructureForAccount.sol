//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
//import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";



contract ccipInfrastructureForAccount is CCIPReceiver
{
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //      "customErrors"                                                                                                                                   ///
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotWhitelisted(uint64 destinationChainSelector); // Used when the destination chain has not been whitelisted by the contract owner.
    error SourceChainNotWhitelisted(uint64 sourceChainSelector); // Used when the source chain has not been whitelisted by the contract owner.
    error SenderNotWhitelisted(address sender); // Used when the sender has not been whitelisted by the contract owner.



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //      "EVENTS"                                                                                                                                         ///
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    event MessageSent
    (
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        string text, // The text being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );
    
    event MessageReceived
    (
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        string text // The text that was received.
    );

    event TokensTransferred
    (
        bytes32 indexed messageId, // The unique ID of the message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        address token, // The token address that was transferred.
        uint256 tokenAmount, // The token amount that was transferred.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the message.
    );



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //      "MODIFIERS"                                                                                                                                      ///
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    modifier onlyWhitelistedDestinationChain(uint64 _destinationChainSelector) 
    {
        if (!whitelistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotWhitelisted(_destinationChainSelector);
        _;
    }

    modifier onlyWhitelistedSourceChain(uint64 _sourceChainSelector) 
    {
        if (!whitelistedSourceChains[_sourceChainSelector])
            revert SourceChainNotWhitelisted(_sourceChainSelector);
        _;
    }

    modifier onlyWhitelistedSenders(address _sender) 
    {
        if (!whitelistedSenders[_sender]) revert SenderNotWhitelisted(_sender);
        _;
    }

    modifier onlyWhitelistedChain(uint64 _destinationChainSelector) 
    {
        if (!whitelistedChains[_destinationChainSelector])
            revert DestinationChainNotWhitelisted(_destinationChainSelector);
        _;
    }



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //      "STORAGE"                                                                                                                                        ///
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////
    //      "VARIABLES"                                        ///
    //////////////////////////////////////////////////////////////
    LinkTokenInterface linkToken;

    //////////////////////////////////////////////////////////////
    //      "interfaceVariables"                               ///
    //////////////////////////////////////////////////////////////
    IRouterClient router;

    //////////////////////////////////////////////////////////////
    //      "MAPPINGS"                                         ///
    //////////////////////////////////////////////////////////////
    mapping(uint64 => bool) public whitelistedDestinationChains;
    mapping(uint64 => bool) public whitelistedSourceChains;
    mapping(address => bool) public whitelistedSenders;
    mapping(uint64 => bool) public whitelistedChains;



    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //      "FUNCTIONS"                                                                                                                                      ///
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////
    //      "CONSTRUCTOR"                                      ///
    //////////////////////////////////////////////////////////////
    constructor(address _router) CCIPReceiver(_router) 
    {
        router = IRouterClient(_router); 
        //destinationChainUsedTokensAddress = paramDestinationTokenAddress;
    }

    //////////////////////////////////////////////////////////////
    //      "ccipWhitelistingFunctions"                        ///
    //////////////////////////////////////////////////////////////
    function whitelistDestinationChain(uint64 _destinationChainSelector) public 
    {
        whitelistedDestinationChains[_destinationChainSelector] = true;
    }

    function denylistDestinationChain(uint64 _destinationChainSelector) public  
    {
        whitelistedDestinationChains[_destinationChainSelector] = false;
    }

    function whitelistSourceChain(uint64 _sourceChainSelector) public  
    {
        whitelistedSourceChains[_sourceChainSelector] = true;
    }

    function denylistSourceChain(uint64 _sourceChainSelector) public  
    {
        whitelistedSourceChains[_sourceChainSelector] = false;
    }

    function whitelistSender(address _sender) public  
    {
        whitelistedSenders[_sender] = true;
    }

    function denySender(address _sender) public  
    {
        whitelistedSenders[_sender] = false;
    }

    function whitelistChain(uint64 _destinationChainSelector) public  
    {
        whitelistedChains[_destinationChainSelector] = true;
    }

    function denylistChain(uint64 _destinationChainSelector) public  
    {
        whitelistedChains[_destinationChainSelector] = false;
    }

    //////////////////////////////////////////////////////////////
    //      "ccipMessaging"                                    ///
    //////////////////////////////////////////////////////////////
    function _buildCCIPMessage(address _receiver, address _token, uint256 _amount, address _feeTokenAddress) internal pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: "", // No data
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit to 0 as we are not sending any data and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 0, strict: false})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
        return evm2AnyMessage;
    }

    // function sendMessagePayLINK(uint64 _destinationChainSelector, address _receiver, string calldata _text) external onlyOwner onlyWhitelistedDestinationChain(_destinationChainSelector) returns (bytes32 messageId)
    // {
    //     // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _funcsBuildCCIPMessage
    //     (
    //         _receiver,
    //         address(0),
    //         1,
    //         address(linkToken)
    //     );

    //     // Initialize a router client instance to interact with cross-chain router
    //     IRouterClient funcRouter = IRouterClient(this.getRouter());

    //     // Get the fee required to send the CCIP message
    //     uint256 fees = funcRouter.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (fees > linkToken.balanceOf(address(this)))
    //         revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

    //     // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
    //     linkToken.approve(address(funcRouter), fees);

    //     // Send the CCIP message through the router and store the returned CCIP message ID
    //     messageId = funcRouter.ccipSend(_destinationChainSelector, evm2AnyMessage);

    //     // Emit an event with message details
    //     emit MessageSent
    //     (
    //         messageId,
    //         _destinationChainSelector,
    //         _receiver,
    //         _text,
    //         address(linkToken),
    //         fees
    //     );

    //     // Return the CCIP message ID
    //     return messageId;
    // }

    // function sendMessagePayNative(uint64 _destinationChainSelector, address addressReceiverContract,
    //     //string calldata _text
    //     address addressToTransfer, uint quantityToTransfer) external onlyOwner onlyWhitelistedDestinationChain(_destinationChainSelector) returns (bytes32 messageId)
    // {
    //     // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _funcsBuildCCIPMessage
    //     (
    //         addressReceiverContract,
    //         addressToTransfer,
    //         quantityToTransfer,
    //         address(0)
    //     );

    //     // Initialize a router client instance to interact with cross-chain router
    //     IRouterClient funcRouter = IRouterClient(this.getRouter());

    //     // Get the fee required to send the CCIP message
    //     uint256 fees = funcRouter.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (fees > address(this).balance)
    //         revert NotEnoughBalance(address(this).balance, fees);

    //     // Send the CCIP message through the router and store the returned CCIP message ID
    //     messageId = funcRouter.ccipSend{value: fees}
    //     (
    //         _destinationChainSelector,
    //         evm2AnyMessage
    //     );

    //     // Emit an event with message details
    //     emit MessageSent
    //     (
    //         messageId,
    //         _destinationChainSelector,
    //         addressReceiverContract,
    //         "sent",
    //         address(0),
    //         fees
    //     );

    //     // Return the CCIP message ID
    //     return messageId;
    // }

    // function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override
    //     onlyWhitelistedSourceChain(any2EvmMessage.sourceChainSelector) // Make sure source chain is whitelisted
    //     onlyWhitelistedSenders(abi.decode(any2EvmMessage.sender, (address))) // Make sure the sender is whitelisted
    // {
    //     (address varAddressToTransfer, uint varQuantityToTransfer) = abi.decode(any2EvmMessage.data, (address, uint));

    //     receivedAddress = varAddressToTransfer;
    //     receivedQuantity = varQuantityToTransfer;


    //     emit MessageReceived
    //     (
    //         any2EvmMessage.messageId,
    //         any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
    //         abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
    //         "received"
    //     );
    // }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal virtual override
        onlyWhitelistedSourceChain(any2EvmMessage.sourceChainSelector) // Make sure source chain is whitelisted
        onlyWhitelistedSenders(abi.decode(any2EvmMessage.sender, (address))) // Make sure the sender is whitelisted
    {
        
        emit MessageReceived
        (
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            "received"
        );
    }

    function _funcsBuildCCIPMessage(address _receiver, address _feeTokenAddress, uint256 operation, string memory name, address nftOrTo, address erc6551Account,  bytes memory data, uint256 value) internal pure returns (Client.EVM2AnyMessage memory) 
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: abi.encode(operation, name, nftOrTo, erc6551Account, data, value), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array aas no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 4_000_000, strict: false})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });

        return evm2AnyMessage;
    }

    // //ccipToken/////////////////////////////////////////////////////////////////
    // function transferTokensPayLINK(uint64 _destinationChainSelector, address _receiver, address _token, uint256 _amount) external onlyOwner onlyWhitelistedChain(_destinationChainSelector) returns (bytes32 messageId)
    // {
    //     // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
    //     //  address(linkToken) means fees are paid in LINK
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
    //         _receiver,
    //         _token,
    //         _amount,
    //         address(linkToken)
    //     );

    //     // Get the fee required to send the message
    //     uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (fees > linkToken.balanceOf(address(this)))
    //         revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);

    //     // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
    //     linkToken.approve(address(router), fees);

    //     // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
    //     IERC20(_token).approve(address(router), _amount);

    //     // Send the message through the router and store the returned message ID
    //     messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

    //     // Emit an event with message details
    //     emit TokensTransferred(
    //         messageId,
    //         _destinationChainSelector,
    //         _receiver,
    //         _token,
    //         _amount,
    //         address(linkToken),
    //         fees
    //     );

    //     // Return the message ID
    //     return messageId;
    // }

    // function transferTokensPayNative(
    //     uint64 _destinationChainSelector,
    //     address _receiver,
    //     //address _token,
    //     uint256 _amount
    // )
    //     external
    //     onlyOwner
    //     onlyWhitelistedChain(_destinationChainSelector)
    //     returns (bytes32 messageId)
    // {
    //     // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
    //     // address(0) means fees are paid in native gas
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
    //         _receiver,
    //         _amount,
    //         address(0)
    //     );

    //     // Get the fee required to send the message
    //     uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (fees > address(this).balance)
    //         revert NotEnoughBalance(address(this).balance, fees);

    //     // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
    //     IERC20(sourceChainUsedTokenAddress).approve(address(router), _amount);

    //     // Send the message through the router and store the returned message ID
    //     messageId = router.ccipSend{value: fees}(
    //         _destinationChainSelector,
    //         evm2AnyMessage
    //     );

    //     // Emit an event with message details
    //     emit TokensTransferred(
    //         messageId,
    //         _destinationChainSelector,
    //         _receiver,
    //         sourceChainUsedTokenAddress,
    //         _amount,
    //         address(0),
    //         fees
    //     );

    //     // Return the message ID
    //     return messageId;
    // }

    

    //////////////////////////////////////////////////////////////
    //      "etherRelatedFunctions"                            ///
    //////////////////////////////////////////////////////////////
    receive() external payable {}

    function withdraw(address _beneficiary) public 
    {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }
}


//chainAbstraction//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // function makeChainAbstractionTransfer(uint64 _destinationChainSelector, address smartContractReceiverAddress, address addressToTransferOnDestination, uint quantityToTransferFromDestination, uint256 quantityToTransferFromSource, address sourceTokenAddress) public
    // {
    //     //ccipFuncs/////////////////////////////////////////////////////////////////
    //     Client.EVM2AnyMessage memory funcEvm2AnyMessage = _funcsBuildCCIPMessage(
    //         smartContractReceiverAddress,
    //         addressToTransferOnDestination,
    //         quantityToTransferFromDestination,
    //         address(0)
    //     );

    //     IRouterClient funcRouter = IRouterClient(this.getRouter());

    //     uint256 fees = funcRouter.getFee(_destinationChainSelector, funcEvm2AnyMessage);

    //     if (fees > address(this).balance)
    //         revert NotEnoughBalance(address(this).balance, fees);

    //     // Send the CCIP message through the router and store the returned CCIP message ID
    //     bytes32 funcMessageId = funcRouter.ccipSend{value: fees}(
    //         _destinationChainSelector,
    //         funcEvm2AnyMessage
    //     );

    //     //ccipToken/////////////////////////////////////////////////////////////////
    //     Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
    //         addressToTransferOnDestination,
    //         sourceChainUsedTokenAddress,
    //         quantityToTransferFromSource,
    //         address(0)
    //     );

    //     uint256 tokenFees = router.getFee(_destinationChainSelector, evm2AnyMessage);

    //     if (tokenFees > address(this).balance)
    //         revert NotEnoughBalance(address(this).balance, fees);

    //     // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
    //     IERC20(sourceChainUsedTokenAddress).approve(address(router), quantityToTransferFromSource);
        
    //     bytes32 tokenMessageId = router.ccipSend{value: fees}(
    //         _destinationChainSelector,
    //         evm2AnyMessage
    //     );
    // }
