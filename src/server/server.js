import 'babel-polyfill';
import FlightSuretyApp from "../../build/contracts/FlightSuretyApp.json";
import Config from "./config.json";
import Web3 from "web3";
import express from "express";
var BigNumber = require('bignumber.js');

let config = Config["localhost"];
let web3 = new Web3(
  new Web3.providers.WebsocketProvider(config.url.replace("http", "ws"))
);
web3.eth.defaultAccount = web3.eth.accounts[0];
let flightSuretyApp = new web3.eth.Contract(
  FlightSuretyApp.abi,
  config.appAddress
);

const oracles = [];

//Edited from https://github.com/ireade/nd1309-flight-surety/blob/master/src/server/server.js
init();
async function init() {
  const accounts = await web3.eth.getAccounts();

  const TEST_ORACLES_COUNT = 21;
  await registerOracles(accounts.slice(1, TEST_ORACLES_COUNT + 1));

  flightSuretyApp.events.OracleRequest({ fromBlock: 0 }, async (error, event) => {

    if (error) return console.log(error);
    if (!event.returnValues) return console.error("No returned values");

    await respondToFetchFlightStatus(
      event.returnValues.index,
      event.returnValues.airline,
      event.returnValues.flight,
      event.returnValues.timestamp
    )
  });
}

async function registerOracles(oracleAccounts) {

  const fee = await flightSuretyApp.methods.REGISTRATION_FEE().call();
  const STATUS_CODES = [0, 10, 20, 30, 40, 50];

  for (let i = 0; i < oracleAccounts.length; i++) {

    const address = oracleAccounts[i];
    const status = STATUS_CODES[Math.floor(Math.random() * STATUS_CODES.length)];

    await flightSuretyApp.methods.registerOracle().send({
      from: address,
      value: fee,
      gas: 3000000
    });

    const indexes = await flightSuretyApp.methods
      .getMyIndexes()
      .call({ from: address });

    oracles.push({ address, indexes, status });
  }

  console.log(`${oracles.length} Oracles Registered`);
}

async function respondToFetchFlightStatus(index, airline, flight, timestamp) {
  console.log(oracles.length);
  if (oracles.length === 0) return;

  console.log("*Received request*")
  console.log(index, airline, flight, timestamp);

  const relevantOracles = [];

  oracles.forEach((oracle) => {
    if (BigNumber(oracle.indexes[0]).isEqualTo(index)) relevantOracles.push(oracle);
    if (BigNumber(oracle.indexes[1]).isEqualTo(index)) relevantOracles.push(oracle);
    if (BigNumber(oracle.indexes[2]).isEqualTo(index)) relevantOracles.push(oracle);
  });

  console.log(`${relevantOracles.length} Matching Oracles will respond`);

  relevantOracles.forEach((oracle) => {
    flightSuretyApp.methods
      .submitOracleResponse(index, airline, flight, timestamp, oracle.status)
      .send({ from: oracle.address, gas: 6000000 })
      .then(() => {
        console.log("Oracle responded with " + oracle.status);
      })
      .catch((err) => console.log("Oracle response rejected"));
  });
}

//Boilerplate
flightSuretyApp.events.OracleRequest(
  {
    fromBlock: 0,
  },
  function (error, event) {
    if (error) console.log("Error:", error);
    console.log("oracle-request", event);
  }
);

const app = express();
app.get("/api", (req, res) => {
  res.send({
    message: "An API for use with your Dapp!",
  });
});

//Functioning oracle
app.get("/", (req, res) => {
  const oracleListening = oracles.filter((oracle) => oracle.isListening);
  res.send(
    `${oracles.length} oracles are instantiating, and ${oracleListening.length} oracles are running`
  );
});

export default app;
