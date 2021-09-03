
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(airline) first airline is registered when contract is deployed`, async function () {
    const isRegistered = await config.flightSuretyData.checkAirlineExists.call(config.firstAirline);
    const isVoter = await config.flightSuretyData.checkAirlineVoter.call(config.firstAirline);
    const checkAirlineApproved = await config.flightSuretyData.checkAirlineApproved.call(config.firstAirline);

    assert.equal(isRegistered, true, "First airline is not registered");
    assert.equal(isVoter, true, "First airline is not voter");
    assert.equal(checkAirlineApproved, true, "First airline is not approved");

  });

  it(`(multiparty) has correct initial isOperational() value`, async function () {

    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");

  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

    // Ensure that access is denied for non-Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
    }
    catch (e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

    // Ensure that access is allowed for Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false);
    }
    catch (e) {
      accessDenied = true;
    }
    assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

    await config.flightSuretyData.setOperatingStatus(false);

    let reverted = false;
    try {
      await config.flightSurety.setTestingMode(true);
    }
    catch (e) {
      reverted = true;
    }
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");

    // Set it back for other tests to work
    await config.flightSuretyData.setOperatingStatus(true);

  });

  it('(airline) only existing airline may register a new airline until there are at least four airlines registered', async () => {
    const addressNoConsensus1 = config.testAddresses[0];
    const addressNoConsensus2 = config.testAddresses[1];
    const addressNoConsensus3 = config.testAddresses[2];

    async function isRegistered(airline) {
      const isRegistered = await config.flightSuretyData.checkAirlineExists.call(airline);
      const checkAirlineApproved = await config.flightSuretyData.checkAirlineApproved.call(airline);
      return (isRegistered && checkAirlineApproved);
    }

    var registeredAirlines = [];
    try {
      await config.flightSuretyApp.registerAirline(addressNoConsensus1, { from: config.firstAirline });
      registeredAirlines.push(await isRegistered(addressNoConsensus1));
      await config.flightSuretyApp.registerAirline(addressNoConsensus2, { from: config.firstAirline });
      registeredAirlines.push(await isRegistered(addressNoConsensus2));
      await config.flightSuretyApp.registerAirline(addressNoConsensus3, { from: config.firstAirline });
      registeredAirlines.push(await isRegistered(addressNoConsensus3));

    } catch (err) {
      console.log(err);
    }
    assert.equal(registeredAirlines[0], true, "Airline 1 could not be registered");
    assert.equal(registeredAirlines[1], true, "Airline 2 could not be registered");
    assert.equal(registeredAirlines[2], true, "Airline 3 could not be registered");
  });

  it('(airline) can be registered, but does not participate in contract until it submits funding of 10 ether', async () => {

    // ARRANGE
    const addressConsesusNeeded = config.testAddresses[3];
    const newAirline = accounts[4];

    // ACT
    let reverted = false;

    try {
      await config.flightSuretyApp.registerAirline(newAirline, { from: addressConsesusNeeded });
      const isVoter = await config.flightSuretyData.checkAirlineVoter.call(newAirline);
    }
    catch (e) {
      reverted = true;
    }

    // ASSERT
    assert.equal(reverted, true, "Registering airline has to be funded to be able to vote");
  });

  it('(airline) contract can be funded by registered airlines', async () => {
    const unfundedAirline = config.testAddresses[1];

    let dataContractAddress = config.flightSuretyData.address;

    const balance = await web3.eth.getBalance(dataContractAddress);
    let isVoter = false

    const funding = web3.utils.toWei("10", "ether");

    try {
      await config.flightSuretyApp.fundAirline({ from: unfundedAirline, value: funding });
      isVoter = await config.flightSuretyData.checkAirlineVoter.call(unfundedAirline);
    } catch (e) {
      console.log("couldn't fund airline", e);
    }
    const newBalance = await web3.eth.getBalance(dataContractAddress);

    assert.equal(newBalance, (Number(balance) + Number(funding)).toString(), "Funding was unsuccesful");
    assert.equal(isVoter, true, "Airline is not voter");
  });

  async function fund(address, _funding) {
    await config.flightSuretyApp.fundAirline({ from: address, value: _funding });
    return await config.flightSuretyData.checkAirlineVoter.call(address);
  }

  it('(airline) fund rest of airlines', async () => {
    //Fund all the first airlines for next tests
    const addressNoConsensus1 = config.testAddresses[0];
    const addressNoConsensus3 = config.testAddresses[2];

    const contractBalance = await web3.eth.getBalance(config.flightSuretyData.address);

    const funding = web3.utils.toWei("10", "ether");

    let voters = [];

    try {
      voters.push(await fund(addressNoConsensus1, funding));
      voters.push(await fund(addressNoConsensus3, funding));
    } catch (e) {
      console.log("couldn't fund airline", e);
    }

    const newContractBalance = await web3.eth.getBalance(config.flightSuretyData.address);

    assert.equal(voters[0], true, "Airline 1 is not funded");
    assert.equal(voters[1], true, "Airline 3 is not funded");
    assert.equal(newContractBalance, (Number(contractBalance) + (Number(funding) * 2)).toString(), "Funding was unsuccesful");
  });

  it('(airline) registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines', async () => {
    //Airline created with contract count as the fourth one.
    const addressConsesusNeeded = config.testAddresses[3];

    const addressNoConsensus1 = config.testAddresses[0];
    const addressNoConsensus2 = config.testAddresses[1];

    async function isApproved(airline) {
      const isRegistered = await config.flightSuretyData.checkAirlineExists.call(airline);
      const checkAirlineApproved = await config.flightSuretyData.checkAirlineApproved.call(airline);
      return (isRegistered && checkAirlineApproved);
    }

    let approved;
    try {
      //Consensus needed
      await config.flightSuretyApp.registerAirline(addressConsesusNeeded, { from: config.firstAirline });
      approved = await isApproved(addressConsesusNeeded);
    } catch (err) {
      console.log(err)
    }
    //Consensus needed
    assert.equal(approved, false, "Airline needs consensus to be aproved");

    //Consensus
    try {
      //Consensus needed
      await config.flightSuretyApp.registerAirline(addressConsesusNeeded, { from: addressNoConsensus1 });
      await config.flightSuretyApp.registerAirline(addressConsesusNeeded, { from: addressNoConsensus2 });
      approved = await isApproved(addressConsesusNeeded);
    } catch (err) {
      console.log(err)
    }
    assert.equal(approved, true, "Consensus not achieved.");
  });

  it('(flight) funded airline can register flights', async () => {
    const registeredAirline = config.testAddresses[1];
    const timestamp = config.timestamp;

    const flight = 'ND1309'; // Course number

    const STATUS_CODE_UNKNOWN = 0;
    const status = STATUS_CODE_UNKNOWN;

    let isRegistered = false;
    try {
      await config.flightSuretyApp.registerFlight(status, flight, timestamp, { from: registeredAirline });
      isRegistered = await config.flightSuretyApp.getFlightIsRegistered.call(registeredAirline, flight, timestamp);
    } catch (err) {
      console.log(err);
    }
    assert.equal(isRegistered, true, "Flight could not be registered");
  });

  it('(passenger) may pay up to 1 ether for purchasing flight insurance', async () => {
    const passenger1 = config.testAddresses[4];
    const dataContractAddress = config.flightSuretyData.address;

    const flight = 'ND1309'; // Course number

    const balance = await web3.eth.getBalance(dataContractAddress);

    const insuranceValue = web3.utils.toWei("1", "ether");

    try {
      await config.flightSuretyApp.buyInsurance(flight, passenger1, { from: passenger1, value: insuranceValue })
    } catch (err) {
      console.log(err);
    }

    const newBalance = await web3.eth.getBalance(dataContractAddress);

    assert.equal(newBalance, (Number(balance) + Number(insuranceValue)).toString(), "Insurance purchase wasn't succesful");
  });

  it('(flight) if is delayed due to airline fault, passenger receives credit of 1.5X the amount paid', async () => {
    const registeredAirline = config.testAddresses[1];
    const passenger1 = config.testAddresses[4];
    const timestamp = config.timestamp;

    const flight = 'ND1309'; // Course number

    const STATUS_CODE_LATE_AIRLINE = 20;

    const creditValue = 1.5; //Insurance value is 1 Ether.

    let creditsBefore, creditsAfter, _creditsBefore, _creditsAfter;

    try {
      _creditsBefore = await config.flightSuretyApp.getInsureePayout(passenger1);
      creditsBefore = web3.utils.fromWei(_creditsBefore, "ether");
      await config.flightSuretyApp.processFlightStatus(registeredAirline, flight, timestamp, STATUS_CODE_LATE_AIRLINE, { from: registeredAirline })
      _creditsAfter = await config.flightSuretyApp.getInsureePayout(passenger1);
      creditsAfter = web3.utils.fromWei(_creditsAfter, "ether");
    } catch (err) {
      console.log(err);
    }

    assert.equal(creditsAfter.toString(), (Number(creditsBefore) + Number(creditValue)).toString(), "Credited value is not calculated as expected.");
  });

  it('(passenger) can withdraw any funds owed to them for insurance payout', async () => {
    const passenger1 = config.testAddresses[4];
    const balance = new BigNumber(await web3.eth.getBalance(passenger1));

    let credits, gasUsed, gasPrice;

    try {
      credits = new BigNumber(await config.flightSuretyApp.getInsureePayout(passenger1));
      const receipt = await config.flightSuretyApp.withdrawPayout({ from: passenger1 })
      gasUsed = new BigNumber(receipt.receipt.gasUsed);
      const tx = await web3.eth.getTransaction(receipt.tx);
      gasPrice = new BigNumber(tx.gasPrice);
    } catch (err) {
      console.log(err);
    }
    const newBalance = new BigNumber(await web3.eth.getBalance(passenger1));

    const isEqual = newBalance.isEqualTo(balance.plus(credits.minus(gasPrice.times(gasUsed))));

    assert.equal(isEqual, true, "Insuree could't withdraw credits");
  });
});