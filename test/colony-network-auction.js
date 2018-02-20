/* globals artifacts */
import { BN } from "bn.js";

import testHelper from "../helpers/test-helper";
import testDataGenerator from "../helpers/test-data-generator";

const EtherRouter = artifacts.require("EtherRouter");
const IColony = artifacts.require("IColony");
const IColonyNetwork = artifacts.require("IColonyNetwork");
const DutchAuction = artifacts.require("DutchAuction");
const Token = artifacts.require("Token");

contract("ColonyNetworkAuction", accounts => {
  const BIDDER_1 = accounts[1];
  const BIDDER_2 = accounts[2];
  const BIDDER_3 = accounts[3];

  let commonColony;
  let colonyNetwork;
  let tokenAuction;
  let startBlock;
  const startPrice = 100;
  const quantity = 3e18;
  let clny;
  let token;

  before(async () => {
    const etherRouter = await EtherRouter.deployed();
    colonyNetwork = await IColonyNetwork.at(etherRouter.address);

    const commonColonyAddress = await colonyNetwork.getColony("Common Colony");
    commonColony = IColony.at(commonColonyAddress);
  });

  beforeEach(async () => {
    clny = await Token.new("Colony Network Token", "CLNY", 18);
    commonColony.setToken(clny.address);
    clny.setOwner(commonColony.address);

    const args = testHelper.getTokenArgs();
    token = await Token.new(...args);
    await token.mint(quantity);
    await token.transfer(colonyNetwork.address, quantity);
    const { tx, logs } = await colonyNetwork.startTokenAuction(token.address, quantity, startPrice);
    const auctionAddress = logs[0].args.auction;
    tokenAuction = await DutchAuction.at(auctionAddress);
    const receipt = await testHelper.web3GetTransactionReceipt(tx);
    startBlock = receipt.blockNumber;
  });

  describe("when starting an auction", async () => {
    it("should initialise auction with correct given parameters", async () => {
      const clnyAddress = await tokenAuction.clnyToken.call();
      assert.equal(clnyAddress, clny.address);
      const tokenAddress = await tokenAuction.token.call();
      assert.equal(tokenAddress, token.address);
      const quantityNow = await tokenAuction.quantity.call();
      assert.equal(quantityNow.toString(), "3000000000000000000");
      const startPriceNow = await tokenAuction.startPrice.call();
      assert.equal(startPrice, startPriceNow.toString());
    });

    it("should initialise auction with correct start block", async () => {
      const startBlockOnContract = await tokenAuction.startBlock.call();
      assert.equal(startBlockOnContract.toNumber(), startBlock);
    });

    it("should not be able to initialise auction with 0x0 token", async () => {
      await testHelper.checkError(colonyNetwork.startTokenAuction("0x0", quantity, startPrice));
    });

    it("should not be able to initialise auction with zero quantity", async () => {
      await testHelper.checkError(colonyNetwork.startTokenAuction(token.address, 0, startPrice));
    });

    it("should not be able to initialise auction with zero start price", async () => {
      await testHelper.checkError(colonyNetwork.startTokenAuction(token.address, quantity, 0));
    });
  });

  describe("when bidding", async () => {
    it("can bid", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "1000000000000000000");
      await clny.approve(tokenAuction.address, "1000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("1000000000000000000", { from: BIDDER_1 });
      const bid = await tokenAuction.bids.call(BIDDER_1);
      assert.equal(bid, "1000000000000000000");
    });

    it("deposit tokens are locked", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "1000000000000000000");
      await clny.approve(tokenAuction.address, "1000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("1000000000000000000", { from: BIDDER_1 });
      const lockedTokens = await clny.balanceOf.call(tokenAuction.address);
      assert.equal(lockedTokens.toString(), "1000000000000000000");
    });

    it("can bid more than once", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "2000000000000000000");
      await clny.approve(tokenAuction.address, "2000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("1100000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("900000000000000000", { from: BIDDER_1 });
    });

    it("if bid overshoots the target quantity, it is only partially accepted", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "300000000000000000000");
      await clny.approve(tokenAuction.address, "300000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("300000000000000000000", { from: BIDDER_1 });
      const totalToEndAuction = await tokenAuction.totalToEndAuction.call();
      const receivedTotal = await tokenAuction.receivedTotal.call();
      const bid = await tokenAuction.bids.call(BIDDER_1);
      assert.equal(bid.toString(), totalToEndAuction.toString());
      assert.equal(receivedTotal.toString(), totalToEndAuction.toString());
    });

    it("after target is sold, bid is rejected", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "30000000000000000000");
      await clny.approve(tokenAuction.address, "30000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("20000000000000000000", { from: BIDDER_1 });
      await testHelper.checkError(tokenAuction.bid("10000000000000000000", { from: BIDDER_1 }));
    });

    it("cannot finalize when target not reached", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "3000");
      await clny.approve(tokenAuction.address, "3000", { from: BIDDER_1 });
      await tokenAuction.bid("3000", { from: BIDDER_1 });
      await testHelper.checkError(tokenAuction.finalize());
    });

    it("cannot bid with 0 tokens", async () => {
      await testHelper.checkError(tokenAuction.bid(0));
    });

    const auctionVars = [
      {
        block: 0,
        price: "100000000000000000000",
        amount: "300000000000000000000"
      },
      {
        block: 1,
        price: "50000000000000000000",
        amount: "150000000000000000000"
      },
      {
        block: 10,
        price: "9090909090909090909",
        amount: "27272727272727272727"
      },
      {
        block: 29,
        price: "3333333333333333333",
        amount: "9999999999999999999"
      },
      {
        block: 45,
        price: "2173913043478260869",
        amount: "6521739130434782607"
      }
    ];

    auctionVars.forEach(async auctionVar => {
      it(`should correctly calculate price and remaining CLNY amount to end auction at elapsed block ${auctionVar.block}`, async () => {
        await testHelper.forwardToBlock(startBlock + auctionVar.block);
        const currentPrice = await tokenAuction.price.call();
        const totalToEndAuction = await tokenAuction.totalToEndAuction.call();
        assert.equal(auctionVar.price, currentPrice.toString());
        assert.equal(auctionVar.amount, totalToEndAuction.toString());
      });
    });
  });

  describe("when finalizing auction", async () => {
    beforeEach(async () => {
      const totalToEndAuction = await tokenAuction.totalToEndAuction.call();
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, totalToEndAuction.toString());
      await clny.approve(tokenAuction.address, totalToEndAuction.toString(), { from: BIDDER_1 });
      await tokenAuction.bid(totalToEndAuction.toString(), { from: BIDDER_1 });
    });

    it("sets correct final token price", async () => {
      const { tx } = await tokenAuction.finalize();
      const receipt = await testHelper.web3GetTransactionReceipt(tx);
      const endBlock = receipt.blockNumber;
      const elapsedBlocks = endBlock - startBlock;
      const endPrice = new BN(10)
        .pow(new BN(18))
        .muln(startPrice)
        .divn(elapsedBlocks);
      const finalPrice = await tokenAuction.finalPrice.call();
      assert.equal(endPrice.toString(), finalPrice.toString());
    });

    it("sets the finalized property", async () => {
      await tokenAuction.finalize();
      const finalized = await tokenAuction.finalized.call();
      assert.isTrue(finalized);
    });

    it("Colony network gets all CLNY sent to the auction in bids", async () => {
      const balanceBefore = await clny.balanceOf.call(colonyNetwork.address);
      await tokenAuction.finalize();
      const receivedTotal = await tokenAuction.receivedTotal.call();
      const balanceAfter = await clny.balanceOf.call(colonyNetwork.address);
      assert.equal(balanceBefore.add(receivedTotal).toString(), balanceAfter.toString());
    });

    it("cannot bid after finalized", async () => {
      await tokenAuction.finalize();
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, 1000);
      await clny.approve(tokenAuction.address, 1000, { from: BIDDER_1 });
      await testHelper.checkError(tokenAuction.bid(1000, { from: BIDDER_1 }));
    });

    it("cannot finalize after finalized once", async () => {
      await tokenAuction.finalize();
      await testHelper.checkError(tokenAuction.finalize());
    });

    it("cannot claim if not finalized", async () => {
      await testHelper.checkError(tokenAuction.claim({ from: BIDDER_1 }));
    });
  });

  describe("when claiming tokens", async () => {
    it("should transfer to bidder correct number of won tokens at finalPrice", async () => {
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, "1000000000000000000");
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_2, "2000000000000000000");
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_3, "1000000000000000000");
      await clny.approve(tokenAuction.address, "1000000000000000000", { from: BIDDER_1 });
      await clny.approve(tokenAuction.address, "2000000000000000000", { from: BIDDER_2 });
      await clny.approve(tokenAuction.address, "1000000000000000000", { from: BIDDER_3 });
      await tokenAuction.bid("1000000000000000000", { from: BIDDER_1 });
      await tokenAuction.bid("2000000000000000000", { from: BIDDER_2 });
      await tokenAuction.bid("1000000000000000000", { from: BIDDER_3 });

      await tokenAuction.finalize();
      const finalPrice = await tokenAuction.finalPrice.call();
      const finalPriceString = finalPrice.toString();

      let tokensClaimed;
      let tokenBidderBalance;
      let tokensToClaim;

      await tokenAuction.claim({ from: BIDDER_1 });
      tokensClaimed = await tokenAuction.tokensClaimed.call();
      assert.equal(tokensClaimed.toString(), "1000000000000000000");
      tokenBidderBalance = await token.balanceOf.call(BIDDER_1);
      tokensToClaim = new BN(10)
        .pow(new BN(18))
        .mul(new BN("1000000000000000000"))
        .div(new BN(finalPriceString));
      assert.equal(tokenBidderBalance.toString(), tokensToClaim);

      await tokenAuction.claim({ from: BIDDER_2 });
      tokensClaimed = await tokenAuction.tokensClaimed.call();
      assert.equal(tokensClaimed.toString(), "3000000000000000000");
      tokenBidderBalance = await token.balanceOf.call(BIDDER_2);
      tokensToClaim = new BN(10)
        .pow(new BN(18))
        .mul(new BN("2000000000000000000"))
        .div(new BN(finalPriceString));
      assert.equal(tokenBidderBalance.toString(), tokensToClaim);

      const bid3 = await tokenAuction.bids.call(BIDDER_3);
      await tokenAuction.claim({ from: BIDDER_3 });
      tokensClaimed = await tokenAuction.tokensClaimed.call();
      assert.equal(tokensClaimed.toString(), bid3.add("3000000000000000000").toString());
      tokenBidderBalance = await token.balanceOf.call(BIDDER_3);
      tokensToClaim = new BN(10)
        .pow(new BN(18))
        .mul(new BN(bid3.toString()))
        .div(new BN(finalPriceString));
      assert.equal(tokenBidderBalance.toString(), tokensToClaim.toString());
    });

    it("should set the bid amount to 0", async () => {
      const totalToEndAuction = await tokenAuction.totalToEndAuction.call();
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, totalToEndAuction.toString());
      await clny.approve(tokenAuction.address, totalToEndAuction.toString(), { from: BIDDER_1 });
      await tokenAuction.bid(totalToEndAuction.toString(), { from: BIDDER_1 });
      await tokenAuction.finalize();
      await tokenAuction.claim({ from: BIDDER_1 });
      const bid = await tokenAuction.bids.call(BIDDER_1);
      assert.equal(bid.toNumber(), 0);
    });
  });

  describe("after all tokens have been claimed", async () => {
    it("should be able to kill auction contract", async () => {
      const totalToEndAuction = await tokenAuction.totalToEndAuction.call();
      await testDataGenerator.giveUserCLNYTokens(colonyNetwork, BIDDER_1, totalToEndAuction.toString());
      await clny.approve(tokenAuction.address, totalToEndAuction.toString(), { from: BIDDER_1 });
      await tokenAuction.bid(totalToEndAuction.toString(), { from: BIDDER_1 });
      await tokenAuction.finalize();
      await tokenAuction.claim({ from: BIDDER_1 });
      await tokenAuction.close();
    });
  });
});
