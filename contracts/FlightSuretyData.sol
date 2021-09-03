pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true;

    uint256 private airlinesCount = 0;

    uint256 private flightCount = 0;

    uint256 private insuranceCount = 0;

    mapping(address => bool) private authorizedCallers;

    //Airlines
    struct Airline {
        uint256 id;
        bool isVoter;
        bool approved;
        uint256 minVotes;
    }

    mapping(address => Airline) private airlines;

    enum InsuranceState {
        Active,
        Expired,
        Credited
    }
    struct Insurance {
        uint256 id;
        uint256 flightId;
        InsuranceState state;
        uint256 insuredAmount;
        address insuree;
    }

    mapping(address => uint256) votes;

    mapping(address => address[]) approvals;

    uint256 maxAutoAprovedAirlines = 4;

    mapping(uint256 => Insurance) private insurances;
    mapping(address => uint256[]) private passengerInsurances;
    mapping(uint256 => uint256[]) private flightInsurances;

    mapping(address => uint256) private insuranceCredits;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event AddedFunds(address contractAddress, uint256 amount);
    event UpdatedCallerIsAuthorized(address contractAddress, bool isAuthorized);

    event RegisteredAirline(address airlineAddres, address registeringAirline);
    event RegisteredVote(address airline, address registeringAirline);
    event UpdatedAirlineIsVoter(address airlineAddress, bool isVoter);
    event UpdatedAirlineVotes(address airlineAddress, bool vote);

    event PurchaseInsurance(
        uint256 flightId,
        address insuree,
        uint256 amountPaid,
        uint256 insuranceCount
    );

    event CreditedInsurance(uint256 insuranceId, uint256 credit);
    event PayedInsurance(address insuree, uint256 credit);

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor(address firstAirline) public payable {
        contractOwner = msg.sender;
        authorizedCallers[address(this)] = true;
        authorizedCallers[contractOwner] = true;

        airlinesCount = airlinesCount.add(1);
        airlines[firstAirline] = Airline({
            id: airlinesCount,
            isVoter: true,
            approved: true,
            minVotes: 0
        });
        address(this).transfer(msg.value);
        emit AddedFunds(address(this), msg.value);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the caller to be authorized
     */
    modifier requireAuthorizedCaller() {
        require(
            authorizedCallers[msg.sender] == true,
            "Caller is not authorized"
        );
        _;
    }

    /**
     * @dev Modifier that requires the Insurance to be valid
     */
    modifier requireValidInsurance(uint256 insuranceId) {
        require(insurances[insuranceId].id > 0, "Insurance is invalid");
        _;
    }

    /**
     * @dev Modifier that requires the insurance to be active
     */
    modifier requireActiveInsurance(uint256 insuranceId) {
        require(
            uint256(insurances[insuranceId].state) == 0,
            "Insurance is not active"
        );
        _;
    }

    modifier requireContractHasEnoughFunds(address insuree) {
        require(
            address(this).balance > insuranceCredits[insuree],
            "Contract does not have enough funds"
        );
        _;
    }

    modifier requireCreditedInsurance(address insuree) {
        require(
            insuranceCredits[insuree] > 0,
            "Insuree does not have any credits"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeCaller(address _contract)
        external
        requireIsOperational
        requireContractOwner
    {
        authorizedCallers[_contract] = true;
        emit UpdatedCallerIsAuthorized(_contract, true);
    }

    function deAuthorizeCaller(address _contract)
        external
        requireIsOperational
        requireContractOwner
    {
        delete authorizedCallers[_contract];
        emit UpdatedCallerIsAuthorized(_contract, false);
    }

    function checkAirlineExists(address airline) external view returns (bool) {
        bool _isAirline = (airlines[airline].id > 0);
        return _isAirline;
    }

    function checkAirlineVoter(address airline) external view returns (bool) {
        return airlines[airline].isVoter;
    }

    function checkAirlineApproved(address airline)
        external
        view
        returns (bool)
    {
        return airlines[airline].approved;
    }

    function getAirlineMinVotes(address airline)
        external
        view
        returns (uint256)
    {
        return airlines[airline].minVotes;
    }

    function getAirlineVotes(address airline) external view returns (uint256) {
        return votes[airline];
    }

    function getMaxAutoAprovedAirlines() external view returns (uint256) {
        return maxAutoAprovedAirlines;
    }

    function setMaxAutoAprovedAirlines(uint256 maxAutoAprovedAirlinesValue)
        external
        requireIsOperational
        requireContractOwner
    {
        maxAutoAprovedAirlines = maxAutoAprovedAirlinesValue;
    }

    function getAirlinesCount() external view returns (uint256) {
        return airlinesCount;
    }

    function getFlightCount() external view returns (uint256) {
        return flightCount;
    }

    function getInsuranceCount() external view returns (uint256) {
        return insuranceCount;
    }

    function getApprovals(address airline)
        external
        view
        returns (address[] memory)
    {
        return approvals[airline];
    }

    function getInsuracesFlight(uint256 flightId)
        external
        view
        returns (uint256[] memory)
    {
        return flightInsurances[flightId];
    }

    function getInsureePayout(address insuree) external view returns (uint256) {
        return insuranceCredits[insuree];
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airline, address registeringAirline)
        external
        requireIsOperational
        requireAuthorizedCaller
    {
        airlinesCount = airlinesCount.add(1);
        airlines[airline] = Airline({
            id: airlinesCount,
            isVoter: false,
            approved: airlinesCount <= maxAutoAprovedAirlines,
            minVotes: airlinesCount.add(1).div(2)
        });
        votes[airline] = votes[airline].add(1);
        approvals[airline].push(registeringAirline);
        emit RegisteredAirline(airline, registeringAirline);
    }

    function registerVote(address airline, address registeringAirline)
        external
        requireIsOperational
        requireAuthorizedCaller
    {
        votes[airline] = votes[airline].add(1);
        approvals[airline].push(registeringAirline);
        emit RegisteredVote(airline, registeringAirline);
    }

    function setFunded(address airline, bool isVoter)
        external
        requireIsOperational
        requireAuthorizedCaller
    {
        airlines[airline].isVoter = isVoter;
        emit UpdatedAirlineIsVoter(airline, isVoter);
    }

    function setApproved(address airline, bool approved)
        external
        requireIsOperational
        requireAuthorizedCaller
    {
        airlines[airline].approved = approved;
        emit UpdatedAirlineVotes(airline, approved);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy(
        uint256 flightId,
        address insuree,
        uint256 amountPaid
    ) external payable requireIsOperational requireAuthorizedCaller {
        insuranceCount = insuranceCount.add(1);

        insurances[insuranceCount] = Insurance({
            id: insuranceCount,
            flightId: flightId,
            state: InsuranceState.Active,
            insuredAmount: amountPaid,
            insuree: insuree
        });

        flightInsurances[flightId].push(insuranceCount);
        passengerInsurances[insuree].push(insuranceCount);
        emit PurchaseInsurance(flightId, insuree, amountPaid, insuranceCount);
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(uint256 insuranceId)
        external
        requireIsOperational
        requireAuthorizedCaller
        requireValidInsurance(insuranceId)
        requireActiveInsurance(insuranceId)
    {
        Insurance memory _insurance = insurances[insuranceId];
        uint256 credit = _insurance.insuredAmount.mul(15).div(10);
        insurances[insuranceId].state = InsuranceState.Credited;
        insuranceCredits[_insurance.insuree] = insuranceCredits[
            _insurance.insuree
        ].add(credit);
        emit CreditedInsurance(insuranceId, credit);
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(address insuree)
        external
        payable
        requireIsOperational
        requireAuthorizedCaller
        requireCreditedInsurance(insuree)
        requireContractHasEnoughFunds(insuree)
    {
        uint256 credit = insuranceCredits[insuree];
        insuranceCredits[insuree] = 0;
        insuree.transfer(credit);
        emit PayedInsurance(insuree, credit);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund() public payable requireIsOperational {
        emit AddedFunds(address(this), msg.value);
    }

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function() external payable {
        emit AddedFunds(address(this), msg.value);
    }
}
