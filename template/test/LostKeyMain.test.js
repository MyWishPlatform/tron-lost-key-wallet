const { BN, time, shouldFail, expectEvent } = require("openzeppelin-test-helpers");

const { promisify } = require("util");

function snapshot() {
  return promisify(web3.currentProvider.send)({
    jsonrpc: "2.0",
    method: "evm_snapshot"
  });
}

function revert(id) {
  return promisify(web3.currentProvider.send)({
    jsonrpc: "2.0",
    method: "evm_revert",
    params: [id]
  });
}

function createTokensArray(count) {
  return Promise.all([...Array(count)].map(_ => TestToken.new()));
}

const LostKey = artifacts.require("LostKeyMain");
const TestToken = artifacts.require("TestToken");

const extractAddress = string => string.match(/\((0x\w+)\)/)[1];
const extractBN = string => new BN(string.match(/\((\d+)\)/)[1]);

const TARGET = "D_TARGET";
const HEIRS_COUNT = D_HEIRS_COUNT;
const HEIRS = "D_HEIRS".split(",").map(extractAddress);
const PERCENTS = "D_PERCENTS".split(",").map(extractBN);
const PERIOD_SECONDS = new BN("D_PERIOD_SECONDS");

contract("LostKeyMain", accounts => {
  let now;
  let snapshotId;

  beforeEach(async () => {
    snapshotId = (await snapshot()).result;
    now = await time.latest();
  });

  afterEach(async () => {
    await revert(snapshotId);
  });

  it("#1 construct", async () => {
    const contract = await LostKey.new();
    contract.address.should.have.length(42);
  });

  it("#2 check parameters", async () => {
    const contract = await LostKey.new();
    (await contract.targetUser()).should.be.equal(TARGET);

    for (let i = 0; i < HEIRS.length; i++) {
      const heirs = await contract.percents(i);
      heirs[0].toLowerCase().should.be.equal(HEIRS[i].toLowerCase());
      heirs[1].should.be.bignumber.equal(PERCENTS[i]);
    }

    (await contract.noActivityPeriod()).should.be.bignumber.equal(PERIOD_SECONDS);
  });

  it("#3 add contract addresses by one", async () => {
    const contract = await LostKey.new();

    for (let i = 0; i < 10; i++) {
      await contract.addTokenAddress((await TestToken.new()).address, { from: TARGET });
    }
    time.increase(PERIOD_SECONDS.add(new BN(1)));
    await contract.check();
  });

  it("#4 add contract addresses batch", async () => {
    const contract = await LostKey.new();
    await contract.addTokenAddresses((await createTokensArray(10)).map(t => t.address), { from: TARGET });

    const tokens = (await createTokensArray(5)).map(t => t.address);
    const { logs } = await contract.addTokenAddresses(tokens, { from: TARGET });

    for (let i = 0; i < logs.length; i++) {
      const {
        event,
        args: { token }
      } = logs[i];
      event.should.be.equal("TokenAdded");
      token.should.be.equal(tokens[i]);
    }

    time.increase(PERIOD_SECONDS.add(new BN(1)));
    await contract.check();
  });

  it("#5 token distribution on check", async () => {
    const tokens = await createTokensArray(2);
    const contract = await LostKey.new();
    await contract.addTokenAddresses(tokens.map(t => t.address), { from: TARGET });

    const heirsCount = HEIRS_COUNT;
    const amount = new BN(1000).mul(new BN(HEIRS_COUNT));

    for (let i = 0; i < tokens.length; i++) {
      await tokens[i].mint(TARGET, amount);
      await tokens[i].approve(contract.address, amount, { from: TARGET });
    }

    time.increase(PERIOD_SECONDS.add(new BN(1)));
    const { logs } = await contract.check();

    for (let t = 0; t < tokens.length; t++) {
      for (let h = 0; h < heirsCount; h++) {
        const heirTokenAmount = amount.mul(PERCENTS[h]).div(new BN(100));
        const { event, args } = logs[t * heirsCount + 2 + h];
        event.should.be.equal("TokensSent");
        args.token.should.be.equal(tokens[t].address);
        args.recipient.toLowerCase().should.be.equal(HEIRS[h].toLowerCase());
        args.percent.should.be.bignumber.equal(PERCENTS[h]);
        args.amount.should.be.bignumber.equal(heirTokenAmount);
        (await tokens[t].balanceOf(HEIRS[h])).should.be.bignumber.equal(heirTokenAmount);
      }
    }
  });

  it("#6 cannot execute contract after kill", async () => {
    const tokens = await createTokensArray(2);
    const contract = await LostKey.new();
    await contract.addTokenAddresses(tokens.map(t => t.address), { from: TARGET });

    const amount = new BN(1000).mul(new BN(HEIRS_COUNT));

    for (let i = 0; i < tokens.length; i++) {
      await tokens[i].mint(TARGET, amount);
      await tokens[i].approve(contract.address, amount, { from: TARGET });
    }

    const { logs } = await contract.kill({ from: TARGET });
    expectEvent.inLogs(logs, "Killed", { byUser: true });

    await shouldFail.reverting(contract.addTokenAddresses((await createTokensArray(1)).map(t => t.address)), {
      from: TARGET
    });
    await time.increase(PERIOD_SECONDS.add(new BN(1)));
    await shouldFail.reverting(contract.check());
  });

  it("#7 i am available", async () => {
    const tokens = await createTokensArray(2);
    const contract = await LostKey.new();
    await contract.addTokenAddresses(tokens.map(t => t.address), { from: TARGET });

    const amount = new BN(1000).mul(new BN(HEIRS_COUNT));

    for (let i = 0; i < tokens.length; i++) {
      await tokens[i].mint(TARGET, amount);
      await tokens[i].approve(contract.address, amount, { from: TARGET });
    }

    const { logs } = await contract.check();
    for (let i = 0; i < logs.length; i++) {
      logs[i].event.should.not.be.equal("Triggered");
    }

    await time.increase(PERIOD_SECONDS.add(new BN(1)));
    const tx = await contract.imAvailable({ from: TARGET });
    (await contract.lastActiveTs()).should.be.bignumber.equal(await time.latest());
    expectEvent.inLogs(tx.logs, "Notified");
  });

  it("#8 check after i am alive", async () => {
    const tokens = await createTokensArray(2);
    const contract = await LostKey.new();
    await contract.addTokenAddresses(tokens.map(t => t.address), { from: TARGET });

    const amount = new BN(1000).mul(new BN(HEIRS_COUNT));

    for (let i = 0; i < tokens.length; i++) {
      await tokens[i].mint(TARGET, amount);
      await tokens[i].approve(contract.address, amount, { from: TARGET });
    }

    const { logs } = await contract.check();
    for (let i = 0; i < logs.length; i++) {
      logs[i].event.should.not.be.equal("Triggered");
    }

    await time.increase(PERIOD_SECONDS.add(new BN(1)));
    await contract.imAvailable({ from: TARGET });

    let tx = await contract.check();
    for (let i = 0; i < tx.logs.length; i++) {
      tx.logs[i].event.should.not.be.equal("Triggered");
    }

    await time.increase(PERIOD_SECONDS.add(new BN(1)));
    tx = await contract.check();
    expectEvent.inLogs(tx.logs, "Triggered");

    await shouldFail.reverting(contract.check());
  });
});
