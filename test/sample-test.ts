import { expect, use } from "chai";
import { solidity } from "ethereum-waffle";
import { ethers } from "hardhat";
import { BasicLoan__factory } from "../typechain/factories/BasicLoan__factory";
import { BasicLoan } from "../typechain/BasicLoan";
import { DAI__factory } from "../typechain/factories/DAI__factory";
import { DAI } from "../typechain/DAI";
import { Signer } from "ethers";

use(solidity);

describe("BasicLoan", function() {
  const ONE_MONTH = 1000 * 60 * 60 * 24 * 30;
  const loanTerms = {
    loanDaiAmount: 100,
    feeDaiAmount: 1,
    repayByTimestamp: Date.now() + ONE_MONTH,
    ethCollateralAmount: 150
  };
  const INITIAL_DAI_SUPPLY = loanTerms.loanDaiAmount + loanTerms.feeDaiAmount;
  let dai: DAI;
  let basicLoan: BasicLoan;
  let lender: Signer;
  let borrower: Signer;
  let snapshotId: string;
  beforeEach(async () => {
    snapshotId = await ethers.provider.send("evm_snapshot", []);
  });
  afterEach(async () => {
    await ethers.provider.send("evm_revert", [snapshotId]);
  });
  before(async () => {
    [lender, borrower] = await ethers.getSigners();
    const DAIFactory = (await ethers.getContractFactory("DAI")) as DAI__factory;
    dai = await DAIFactory.deploy(INITIAL_DAI_SUPPLY);
    await dai.deployed();
    const BasicLoanFactory = (await ethers.getContractFactory("BasicLoan")) as BasicLoan__factory;
    basicLoan = (await BasicLoanFactory.deploy(loanTerms, dai.address)) as any;
    await basicLoan.deployed();
  });
  it("Can repay the loan", async function() {
    // Fund loan
    await dai.connect(lender).increaseAllowance(basicLoan.address, loanTerms.loanDaiAmount);
    await basicLoan.connect(lender).fundLoan();
    // Take loan
    await expect(() =>
      basicLoan.connect(borrower).takeALoanAndAcceptLoanTerms({
        value: loanTerms.ethCollateralAmount
      })
    ).to.changeTokenBalances(dai, [borrower, basicLoan], [loanTerms.loanDaiAmount, -loanTerms.loanDaiAmount]);
    // Transfer DAI for fees
    await dai.connect(lender).transfer(await borrower.getAddress(), loanTerms.feeDaiAmount);
    // // Set allowance to repay
    await dai.connect(borrower).increaseAllowance(basicLoan.address, loanTerms.loanDaiAmount + loanTerms.feeDaiAmount);
    // // Repay the loan
    await expect(await basicLoan.connect(borrower).repay()).to.changeEtherBalances(
      [borrower, basicLoan],
      [loanTerms.ethCollateralAmount, -loanTerms.ethCollateralAmount]
    );
  });

  it("Can liquidate the loan", async function() {
    // Fund loan
    await dai.connect(lender).increaseAllowance(basicLoan.address, loanTerms.loanDaiAmount);
    await basicLoan.connect(lender).fundLoan();
    // Take loan
    await expect(() =>
      basicLoan.connect(borrower).takeALoanAndAcceptLoanTerms({
        value: loanTerms.ethCollateralAmount
      })
    ).to.changeTokenBalances(dai, [borrower, basicLoan], [loanTerms.loanDaiAmount, -loanTerms.loanDaiAmount]);
    // Increase time
    ethers.provider.send("evm_setNextBlockTimestamp", [loanTerms.repayByTimestamp]);
    // Liquidate the loan
    await expect(await basicLoan.connect(lender).liquidate()).to.changeEtherBalances(
      [lender, basicLoan],
      [loanTerms.ethCollateralAmount, -loanTerms.ethCollateralAmount]
    );
  });
});
