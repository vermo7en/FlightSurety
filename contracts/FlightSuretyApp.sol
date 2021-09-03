pragma solidity ^0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; 

    FlightSuretyData dataContract;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    bool private operationalContract = true;

    bool private operational = true;

    uint256 private flightCount = 0;

    address[] voters = new address[](0);

    //Events
    event ApprovedAirline(
        address airline,
        address registeringAirline,
        bool requiredConsensus
    );
    event RegisteredAirline(
        address airline,
        uint256 currentVotes,
        uint256 requiredVotes
    );
    event RegisteredFlight(
        uint8 status,
        string flight,
        uint256 timestamp,
        address airline
    );
    event CreditedInsurances(uint256 flightId, uint256 insuranceCount);
    event PurchasedInsurance(string flight, address insuree, uint256 amount);
    event WithdrawnPayout(address insuree);
    event FundedAirline(address airline, uint256 fund);

    address private contractOwner;
    mapping(address => bool) authorizedCallers;

    struct Flight {
        bool isRegistered;
        uint8 status;
        uint256 updatedTimestamp;
        address airline;
        string flight;
        uint256 id;
    }

    mapping(bytes32 => Flight) private flights;
    mapping(string => uint256) private flightIds;

    uint256 public airlineRegistrationFee = 10 ether;
    uint256 public insuranceCap = 1 ether;

    address _dataContractAddress;

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operationalContract, "Contract is currently not operational");
        _; 
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the airline to fulfill a minimun funding
     */
    modifier requireMinimumFunding() {
        require(
            msg.value >= airlineRegistrationFee,
            "Funding requirement not met"
        );
        _;
    }

    /**
     * @dev Modifier that requires the airline to be a voter
     */
    modifier requireMinimunInsurance() {
        require(msg.value > 0, "Insurance value cannot be 0");
        _;
    }

    /**
     * @dev Modifier that requires the airline to be registered
     */
    modifier requireAirlineIsApproved(address airline) {
        require(
            dataContract.checkAirlineApproved(airline) == true,
            "Airline is not registered"
        );
        _;
    }

    /**
     * @dev Modifier that requires the airline to not be registered
     */
    modifier requireAirlineNotApproved(address airline) {
        require(
            dataContract.checkAirlineApproved(airline) == false,
            "The airline is already registered"
        );
        _;
    }

    /**
     * @dev Modifier that requires the airline to not be registered
     */
    modifier requireAirlineNotFunded(address airline) {
        require(
            dataContract.checkAirlineVoter(airline) == false,
            "The airline is already funded"
        );
        _;
    }

    /**
     * @dev Modifier that requires the airline to be a voter
     */
    modifier requireAirlineIsVoter(address airline) {
        require(
            dataContract.checkAirlineVoter(airline) == true,
            "Airline is not allowed to vote"
        );
        _;
    }

    modifier requireFlightIdRegistered(string memory flight) {
        require(flightIds[flight] > 0, "Flight id is not registered");
        _;
    }

    modifier insureeHasCredits(address insuree) {
        require(this.getInsureePayout(insuree) > 0, "Insuree has no credits");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address dataContractAddress) public payable {
        contractOwner = msg.sender;
        authorizedCallers[address(this)] = true;
        authorizedCallers[contractOwner] = true;

        dataContract = FlightSuretyData(dataContractAddress);
        _dataContractAddress = dataContractAddress;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return operationalContract; // Modify to call data contract's status
    }

    function getInsuranceCap() public view returns (uint256) {
        return insuranceCap;
    }

    function setInsuranceCap(uint256 cap)
        external
        requireIsOperational
        requireContractOwner
    {
        insuranceCap = cap;
    }

    function getAirlineRegistrationFee() public view returns (uint256) {
        return airlineRegistrationFee;
    }

    function setAirlineRegistrationFee(uint256 fee)
        external
        requireIsOperational
        requireContractOwner
    {
        airlineRegistrationFee = fee;
    }

    function getFlightCount() external view returns (uint256) {
        return flightCount;
    }

    function getFlightIsRegistered(
        address airline,
        string flight,
        uint256 timestamp
    ) external view returns (bool) {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        return flights[flightKey].isRegistered;
    }

    function getInsureePayout(address insuree) external view returns (uint256) {
        return dataContract.getInsureePayout(insuree);
    }

    function checkAirlineExists(address airline) public view returns (bool) {
        return dataContract.checkAirlineExists(airline);
    }

    function checkAirlineVoter(address airline) public view returns (bool) {
        return dataContract.checkAirlineVoter(airline);
    }

    function checkAirlineApproved(address airline) public view returns (bool) {
        return dataContract.checkAirlineApproved(airline);
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *
     */
    function registerAirline(address airline)
        external
        requireIsOperational
        requireAirlineIsApproved(msg.sender)
        requireAirlineIsVoter(msg.sender)
        requireAirlineNotApproved(airline)
    {
        uint256 maxAutoApprovedAirlines = dataContract
            .getMaxAutoAprovedAirlines();
        uint256 minVotes = dataContract.getAirlineMinVotes(airline);
        uint256 votes = dataContract.getAirlineVotes(airline);

        uint256 airlinesCount = dataContract.getAirlinesCount();

        if (airlinesCount <= maxAutoApprovedAirlines) {
            //Consensus not required
            dataContract.registerAirline(airline, msg.sender);
            emit ApprovedAirline(airline, msg.sender, false);
        } else {
            //Requires consensus
            if (votes >= minVotes) {
                //approved
                dataContract.setApproved(airline, true);
                emit ApprovedAirline(airline, msg.sender, true);
            } else {
                //Not approved
                address[] memory approvals = dataContract.getApprovals(airline);
                for (uint256 i = 0; i < approvals.length; i++) {
                    require(
                        approvals[i] != msg.sender,
                        "Airline already voted for approval"
                    );
                }
                dataContract.registerVote(airline, msg.sender);
                votes = dataContract.getAirlineVotes(airline);
                if (votes >= minVotes) {
                    dataContract.setApproved(airline, true);
                    emit RegisteredAirline(airline, votes, minVotes);
                }
            }
        }
    }

    /**
     * @dev Register a future flight for insuring.
     *
     */
    function registerFlight(
        uint8 status,
        string flight,
        uint256 timestamp
    ) external requireIsOperational requireAirlineIsVoter(msg.sender) {
        bytes32 flightKey = getFlightKey(msg.sender, flight, timestamp);
        flightCount = flightCount.add(1);
        flights[flightKey] = Flight(
            true,
            status,
            timestamp,
            msg.sender,
            flight,
            flightCount
        );
        flightIds[flight] = flightCount;
        emit RegisteredFlight(status, flight, timestamp, msg.sender);
    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */
    function processFlightStatus(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 status
    ) public requireIsOperational {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        flights[flightKey].status = status;

        if (status == STATUS_CODE_LATE_AIRLINE) {
            creditInsurance(flightIds[flight]);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string flight,
        uint256 timestamp
    ) external {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, airline, flight, timestamp);
    }

    function creditInsurance(uint256 flightId) private requireIsOperational {
        uint256[] memory insurancesFlight = dataContract.getInsuracesFlight(
            flightId
        );
        for (uint256 i = 0; i < insurancesFlight.length; i++) {
            dataContract.creditInsurees(insurancesFlight[i]);
        }
        emit CreditedInsurances(flightId, insurancesFlight.length);
    }

    function buyInsurance(string flight, address insuree)
        external
        payable
        requireIsOperational
        requireMinimunInsurance
        requireFlightIdRegistered(flight)
    {
        uint256 amountPaid;
        if (msg.value >= insuranceCap) {
            amountPaid = insuranceCap;
        } else {
            amountPaid = msg.value;
        }

        uint256 amountToReturn = msg.value.sub(amountPaid);
        dataContract.buy(flightIds[flight], insuree, amountPaid);
        address(dataContract).transfer(amountPaid);
        address(msg.sender).transfer(amountToReturn);
        emit PurchasedInsurance(flight, insuree, msg.value);
    }

    function fundAirline()
        external
        payable
        requireIsOperational
        requireMinimumFunding
        requireAirlineNotFunded(msg.sender)
    {
        address(dataContract).transfer(msg.value);
        dataContract.setFunded(msg.sender, true);
        emit FundedAirline(msg.sender, msg.value);
    }

    function withdrawPayout()
        external
        payable
        requireIsOperational
        insureeHasCredits(msg.sender)
    {
        dataContract.pay(msg.sender);
        emit WithdrawnPayout(msg.sender);
    }

    /********************************************************************************************/
    /*                                    ORACLE MANAGEMENT                                     */
    /********************************************************************************************/

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );

    // Register an oracle with the contract
    function registerOracle() external payable {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3] memory) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    ) external {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[status].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, status);
        if (
            oracleResponses[key].responses[status].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, status);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, status);
        }
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account)
        internal
        returns (uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }
}

contract FlightSuretyData {
    //Utility functions
    function isOperational() public view returns (bool);

    function checkAirlineExists(address airline) public view returns (bool);

    function checkAirlineVoter(address airline) public view returns (bool);

    function checkAirlineApproved(address airline) public view returns (bool);

    function getAirlineMinVotes(address airline) public view returns (uint256);

    function getAirlineVotes(address airline) public view returns (uint256);

    function getAirlinesCount() public view returns (uint256);

    function getFlightCount() public view returns (uint256);

    function getInsuranceCount() public view returns (uint256);

    function getMaxAutoAprovedAirlines() public view returns (uint256);

    function getInsuracesFlight(uint256 flightId)
        external
        view
        returns (uint256[] memory);

    function getInsureePayout(address insuree) external view returns (uint256);

    //Contract functions
    function registerAirline(address airline, address registeredAirline)
        public
        payable;

    function registerVote(address airline, address registeringAirline) public;

    function getApprovals(address airline) public returns (address[]);

    function setApproved(address airline, bool approved) public;

    function setFunded(address airline, bool isVoter) public;

    function creditInsurees(uint256 insuranceId) public;

    function buy(
        uint256 flightId,
        address insuree,
        uint256 amountPaid
    ) public payable;

    function pay(address insuree) public payable;

    function fund() public payable;

    function() external payable;
}
