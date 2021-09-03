import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import Config from './config.json';
import Web3 from 'web3';

export default class Contract {
    constructor(network, callback) {

        let config = Config[network];
        this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
        this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
        this.initialize(callback);
        this.owner = null;
        this.airlines = [];
        this.passengers = [];
    }

    async initialize(callback) {
        this.web3.eth.getAccounts((error, accts) => {

            this.owner = accts[0];

            let counter = 1;

            while (this.airlines.length < 5) {
                this.airlines.push(accts[counter++]);
            }

            while (this.passengers.length < 5) {
                this.passengers.push(accts[counter++]);
            }

            callback();
        });
        try {
            await this.flightSuretyData.methods.authorizeCallerContract(this.config.appAddress).send({ from: this.owner })
        } catch (e) { }
    }

    isOperational(callback) {
        let self = this;
        self.flightSuretyApp.methods
            .isOperational()
            .call({ from: self.owner }, callback);
    }

    async fetchFlightStatus(flight, airline, timestamp, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .fetchFlightStatus(airline, flight, timestamp)
            .send({ from: self.airlines[0] }, async (error, result) => {
                callback(error, { flight: flight, airline: airline, timestamp: timestamp });
            });
    }

    registerAirline(airline, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .registerAirline(airline)
            .send({ from: self.airlines[0], gas: 1500000 }, (error, result) => {
                callback(error, airline, result);
            });
    }

    fundAirline(airline, fund, callback) {
        let self = this;
        const _fund = self.web3.utils.toWei(fund, "ether");
        self.flightSuretyApp.methods
            .fundAirline()
            .send({ from: airline, value: _fund, gas: 1500000 }, (error, result) => {
                (error) && console.error(error);
                callback(error, result);
            });
    }

    registerFlight(status, flight, timestamp, registeringAirline, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .registerFlight(status, flight, timestamp)
            .send({ from: registeringAirline, gas: 1500000 }, (error, result) => {
                callback(error, result);
            });
    }

    buyInsurance(flight, passenger, insuranceValue, callback) {
        let self = this;
        const _insuranceValue = self.web3.utils.toWei(insuranceValue, "ether");

        self.flightSuretyApp.methods
            .buyInsurance(flight, passenger)
            .send({ from: passenger, value: _insuranceValue, gas: 1500000 }, (error, result) => {
                callback(error, result);
            })
    }

    getInsureePayout(passenger, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .getInsureePayout(passenger)
            .call({ from: self.owner }, (error, result) => {
                callback(error, self.web3.utils.fromWei(result, "ether"));
            })
    }

    withdrawPayout(passenger, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .withdrawPayout()
            .send({ from: passenger, gas: 1500000 }, (error, result) => {
                callback(error, result);
            })
    }

    changeOperatingStatus(callback) {
        let self = this;
        self.flightSuretyApp.methods
            .isOperational()
            .call({ from: self.owner }, (error, response) => {
                self.flightSuretyApp.methods
                    .setOperatingStatus(!response)
                    .send({ from: self.owner }, (_error, _response) => {
                        callback(_error, _response);
                    })
            });
    }

    checkAirlineExists(airline, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .checkAirlineExists(airline)
            .call({ from: self.owner }, (error, result) => {
                callback(error, result);
            });
    }

    checkAirlineVoter(airline, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .checkAirlineVoter(airline)
            .call({ from: self.owner }, (error, result) => {
                callback(error, result);
            });
    }

    checkAirlineApproved(airline, callback) {
        let self = this;
        self.flightSuretyApp.methods
            .checkAirlineApproved(airline)
            .call({ from: self.owner }, (error, result) => {
                callback(error, result);
            });
    }
}