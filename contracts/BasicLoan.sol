// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import {DAI} from "./DAI.sol";

/**
 * Basic debt contract allows to borrow DAI for a fixed period of time using ETH as a collateral.
 * Fee is constant and predefined. In case of the lack of payment - the whole collateral
 * will be liquidated and transfered to the lender.
 *
 * DISCLAIMER: Not audited. Do not use with any real value
 */
contract BasicLoan {
    // The scructure defining the basic terms of the loan
    struct Terms {
        // The amount of DAI to be loaned
        uint256 loanDaiAmount;
        // The amount of DAI to be repayed on top of the loan amount as a fee
        uint256 feeDaiAmount;
        // The amount of the colateral in ETH. Should be more valuable then the loanDaiAmount + feeDaiAmount at any time during the loan
        // Otherwise - the borrower has an incentive to default on the loan
        uint256 ethCollateralAmount;
        // The timestamp by which the loan should be repayed. After it - the lender can liquidate the collateral
        uint256 repayByTimestamp;
    }
    Terms public terms;

    // The loan can be in 5 states. Created, Funded, Taken, Repayed, Liquidated
    // Here we define only two because in the latter two - the contract will be destroyed
    enum LoanState {Created, Funded, Taken}
    LoanState public state;

    address payable public lender;
    address payable public borrower;
    address public daiAddress;

    constructor(Terms memory _terms, address _daiAddress) {
        terms = _terms;
        daiAddress = _daiAddress;
        lender = msg.sender;
        state = LoanState.Created;
    }

    // Modifier that prevents some functions to be callen in any other state than the provided one.
    modifier onlyInState(LoanState expectedState) {
        require(state == expectedState, "Not allowed in this state");
        _;
    }

    function fundLoan() public onlyInState(LoanState.Created) {
        // Transfer DAI from the lender to the contract so that we can later transfer it to the borrower as a loan
        // This required the lender to allow us to do so beforehand and will fail otherwise
        state = LoanState.Funded;
        DAI(daiAddress).transferFrom(msg.sender, address(this), terms.loanDaiAmount);
    }

    // Function to take the loan
    function takeALoanAndAcceptLoanTerms()
        public
        payable
        /* Collateral should be transfered when calling this function */
        /* Prevents the loan from being taken twice */
        onlyInState(LoanState.Funded)
    {
        // Check that the exact amount of the collateral is transfered. It will be kept in the contract till the loan is repayed or liquidated
        require(msg.value == terms.ethCollateralAmount, "Invalid collateral amount");
        // Record the borrower address so that only he/she/it can repay the loan and unlock the collateral
        borrower = msg.sender;
        state = LoanState.Taken;
        // Transfer the actual tokens that are being loaned
        DAI(daiAddress).transfer(borrower, terms.loanDaiAmount);
    }

    // Function to repay the loan. It can be repayed early with no fees. Borrower should allow this contract to pull the tokens before calling this.
    function repay() public onlyInState(LoanState.Taken) {
        // Allowing anyone to repay would allow anyone to unlock the collateral
        require(msg.sender == borrower, "Only the borrower can repay the loan");
        // Pull the tokens. Both the initial amount and the fee. If there is not enough - it will fail.
        DAI(daiAddress).transferFrom(borrower, lender, terms.loanDaiAmount + terms.feeDaiAmount);
        // Send the collateral back to the borrower and destroy the contract
        selfdestruct(borrower);
    }

    // This function is to be called by the lender in case the loan is not repayed on time.
    // It will transfer the whole collateral to the lender. The collateral is expected to be
    // more valuable than the loan so that the lender doesn't loose any money in this case.
    function liquidate() public onlyInState(LoanState.Taken) {
        require(msg.sender == lender, "Only the lender can liquidate the loan");
        require(block.timestamp >= terms.repayByTimestamp, "Can not liquidate before the loan is due");
        // Send the collateral to the lender and destroy the contract
        selfdestruct(lender);
    }
}
