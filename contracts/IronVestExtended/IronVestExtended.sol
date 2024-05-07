// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./IronVestPreCheck.sol";

/// @author The ferrum network.
/// @title This is a vesting contract named as IronVest.
/// @dev This contract is upgradeable please use a framework i.e truffle or hardhat for deploying it.
/// @notice This contract contains the power of accesscontrol.
/// There are two different vesting defined in the contract with different functionalities.
/// Have fun reading it. Hopefully it's bug-free. God Bless.
contract IronVestExtended is
    Initializable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    /// @notice Declaration of token interface with SafeErc20.
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @notice This struct will save all the pool information about simple vesting i.e addVesting().
    struct PoolInfo {
        string poolName;
        uint256 startTime; /// block.timestamp while creating new pool.
        uint256 vestingEndTime; /// time stamp when to end the vesting.
        address tokenAddress; /// token which we want to vest in the contract.
        uint256 totalVestedTokens; /// total amount of tokens.
        address[] usersAddresses; /// addresses of users an array.
        uint256[] usersAlloc; /// allocation to user with respect to usersAddresses.
    }

    /// @notice Used to store information about the user in simple vesting.
    struct UserInfo {
        uint256 allocation; /// total allocation to a user.
        uint256 claimedAmount; /// claimedAmnt + claimed.
        uint256 remainingToBeClaimable; /// remaining claimable fully claimable once time ended.
        uint256 lastWithdrawal; /// block.timestamp used for internal claimable calculation
        uint256 releaseRatePerSec; /// calculated as vestingTime/(vestingTime-starttime)
        bool deprecated; /// The allocated address is deprecated and new address allocated.
        address updatedAddress; /// If (deprecated = true) otherwise it will denote address(0x00)
    }

    /// @notice This struct will save all the pool information about simple vesting i.e addCliffVesting().
    struct CliffPoolInfo {
        string poolName;
        uint256 startTime; /// block.timestamp while creating new pool.
        uint256 vestingEndTime; /// total time to end cliff vesting.
        uint256 cliffVestingEndTime; /// time in which user can vest cliff tokens should be less than vestingendtime.
        uint256 nonCliffVestingPeriod; /// calculated as cliffPeriod-vestingEndTime. in seconds
        uint256 cliffPeriodEndTime; ///in this time tenure the tokens keep locked in contract. a timestamp
        address tokenAddress; /// token which we want to vest in the contract.
        uint256 totalVestedTokens; /// total amount of tokens.
        uint256 cliffLockPercentage10000; /// for percentage calculation using 10000 instead 100.
        address[] usersAddresses; /// addresses of users an array.
        uint256[] usersAlloc; /// allocation to user with respect to usersAddresses.
    }

    /// @notice Used to store information about the user in cliff vesting.
    struct UserCliffInfo {
        uint256 allocation; /// total allocation cliff+noncliff
        uint256 cliffAlloc; /// (totalallocation*cliffPercentage)/10000
        uint256 claimedAmnt; /// claimedAmnt-claimableClaimed.
        uint256 tokensReleaseTime; /// the time we used to start vesting tokens.
        uint256 remainingToBeClaimableCliff; /// remaining claimable fully claimable once time ended.
        uint256 cliffReleaseRatePerSec; /// calculated as cliffAlloc/(cliffendtime -cliffPeriodendtime).
        uint256 cliffLastWithdrawal; /// block.timestamp used for internal claimable calculation.
        bool deprecated; /// The allocated address is deprecated and new address allocated.
        address updatedAddress; /// If (deprecated = true) otherwise it will denote address(0x00)
    }

    /// @notice Used to store information about the user of non cliff in cliff vesting.
    struct UserNonCliffInfo {
        uint256 allocation; /// total allocation cliff+noncliff
        uint256 nonCliffAlloc; /// (totalallocation-cliffalloc)
        uint256 claimedAmnt; /// claimedAmnt-claimableClaimed
        uint256 tokensReleaseTime; /// the time we used to start vesting tokens.
        uint256 remainingToBeClaimableNonCliff; /// remaining claimable fully claimable once time ended.
        uint256 nonCliffReleaseRatePerSec; /// calculated as nonCliffAlloc/(cliffVestingEndTime-vestingEndTime).
        uint256 nonCliffLastWithdrawal; /// used for internal claimable calculation.
        bool deprecated; /// The allocated address is deprecated and new address allocated.
        address updatedAddress; /// If (deprecated = true) otherwise it will denote address(0x00)
    }

    /// @notice Vester role initialization.
    bytes32 public constant VESTER_ROLE = keccak256("VESTER_ROLE");
    // @notice IronVest pre checks contract
    IronVestPreCheck public VestingCheck;
    /// @notice Public variable to store contract name.
    string public vestingContractName;
    /// @notice Unique identity of contract.
    uint256 public vestingPoolSize;
    /// @notice Signer address. Transaction supposed to be sign be this address.
    address public signer;
    /// Cliff mapping with the check if the specific pool relate to the cliff vesting or not.
    mapping(uint256 => bool) public cliff;
    /// Double mapping to check user information by address and poolid for cliff vesting.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// Double mapping to check user information by address and poolid for cliff vesting.
    mapping(uint256 => mapping(address => UserCliffInfo)) public userCliffInfo;
    /// Double mapping to check user information by address and poolid for cliff vesting.
    mapping(uint256 => mapping(address => UserNonCliffInfo))
        public userNonCliffInfo;
    // Get updated address from outdated address
    mapping(address => address) public deprecatedAddressOf;
    /// Hash Information to avoid the replay from same _messageHash
    mapping(bytes32 => bool) public usedHashes;
    /// Pool information against specific poolid for simple vesting.
    mapping(uint256 => PoolInfo) internal _poolInfo;
    /// Pool information against specific poolid for cliff vesting.
    mapping(uint256 => CliffPoolInfo) internal _cliffPoolInfo;
    // Total tokens need against a specific address
    mapping(address => uint256) internal _totalVestedTokens;

    /// @dev Creating events for all necessary values while adding simple vesting.
    /// @notice vester address and poolId are indexed.
    event AddVesting(
        address indexed vester,
        uint256 indexed poolId,
        string poolName,
        uint256 startTime,
        uint256 vestingEndTime,
        address tokenAddress,
        uint256 totalVestedTokens,
        address[] usersAddresses,
        uint256[] usersAlloc
    );

    /// @dev Creating events for all necessary values while adding cliff vesting.
    /// @notice vester address and poolId are indexed.
    event CliffAddVesting(
        address indexed vester,
        uint256 indexed poolId,
        string poolName,
        uint256 vestingEndTime,
        uint256 cliffVestingEndTime,
        uint256 cliffPeriodEndTime,
        address tokenAddress,
        uint256 totalVestedTokens,
        address[] usersAddresses,
        uint256[] usersAlloc
    );

    /// @dev Whenever user claim their amount from simple vesting.
    /// @notice beneficiary address and poolId are indexed.
    event Claim(
        uint256 indexed poolId,
        uint256 claimed,
        address indexed beneficiary,
        uint256 remaining
    );

    /// @dev Whenever user claim their cliff amount from cliff vesting.
    /// @notice beneficiary address and poolId are indexed.
    event CliffClaim(
        uint256 indexed poolId,
        uint256 claimed,
        address indexed beneficiary,
        uint256 remaining
    );

    /// @dev Whenever user claim their non cliff amount from cliff vesting.
    /// @notice beneficiary address and poolId are indexed.
    event NonCliffClaim(
        uint256 indexed poolId,
        uint256 claimed,
        address indexed beneficiary,
        uint256 remaining
    );

    /// @dev This event will emit if there is a need to update allocation to new address.
    /// @notice Deprecated, updated address and poolId indexed
    event UpdateBeneficiaryWithdrawalAddress(
        uint256 indexed poolId,
        address indexed deprecatedAddress,
        address indexed newAddress,
        bool isCliff
    );

    /// @notice Modifier to check if vester.
    modifier onlyVester() {
        require(
            hasRole(VESTER_ROLE, _msgSender()),
            "AccessDenied : Only Vester Call This Function"
        );
        _;
    }

    /// @notice Modifier to check if DEFAULT_ADMIN and Deployer of contract.
    modifier onlyOwner() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "AccessDenied : Only Admin Call This Function"
        );
        _;
    }

    /// @dev deploy the contract by upgradeable proxy by any framewrok.
    /// @param _signer : An address verification for facing the replay attack issues.
    /// @notice Contract is upgradeable need initialization and deployer is default admin.
    function initialize(
        string memory _vestingName,
        address _signer,
        address _default_Admin,
        IronVestPreCheck _ironVestPreCheckAddress
    ) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        vestingContractName = _vestingName;
        VestingCheck = _ironVestPreCheckAddress;
        _setupRole(DEFAULT_ADMIN_ROLE, _default_Admin);
        _setupRole(VESTER_ROLE, _default_Admin);
        signer = _signer;
    }

    /// @dev Only callable by vester.
    /// @param _poolName : Pool name is supposed to be any string.
    /// @param _vestingEndTime : Vesting time is tenure in which token will be released.
    /// @param _tokenAddress : Token address related to the vested token.
    /// @param _usersAddresses : Users addresses whom the vester want to allocate tokens and it is an array.
    /// @param _userAlloc : Users allocation of tokens with respect to address.
    /// @param _signature : Signature of the signed by signer.
    /// @param _keyHash : Specific keyhash value formed to stop replay.
    /// @notice Create a new vesting.
    function addVesting(
        string memory _poolName,
        uint256 _vestingEndTime,
        address _tokenAddress,
        address[] memory _usersAddresses,
        uint256[] memory _userAlloc,
        bytes memory _signature,
        bytes memory _keyHash
    ) external onlyVester nonReentrant {
        VestingCheck.preAddVesting(
            _vestingEndTime,
            _usersAddresses,
            _userAlloc
        );
        require(
            signatureVerification(
                _signature,
                _poolName,
                _tokenAddress,
                _keyHash
            ) == signer,
            "Signer : Invalid signer"
        );
        uint256 totalVesting;
        for (uint256 i = 0; i < _usersAddresses.length; i++) {
            totalVesting += _userAlloc[i];
            userInfo[vestingPoolSize][_usersAddresses[i]] = UserInfo(
                _userAlloc[i],
                0,
                _userAlloc[i],
                block.timestamp,
                _userAlloc[i] / (_vestingEndTime - block.timestamp),
                false,
                address(0x00)
            );
        }
        _poolInfo[vestingPoolSize] = PoolInfo(
            _poolName,
            block.timestamp,
            _vestingEndTime,
            _tokenAddress,
            totalVesting,
            _usersAddresses,
            _userAlloc
        );
        IERC20Upgradeable(_tokenAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            totalVesting
        );
        usedHashes[
            VestingCheck.messageHash(_poolName, _tokenAddress, _keyHash)
        ] = true;
        _totalVestedTokens[_tokenAddress] += totalVesting;
        emit AddVesting(
            _msgSender(),
            vestingPoolSize,
            _poolName,
            block.timestamp,
            _vestingEndTime,
            _tokenAddress,
            totalVesting,
            _usersAddresses,
            _userAlloc
        );
        vestingPoolSize = vestingPoolSize + 1;
    }

    /// @dev User must have allocation in the pool.
    /// @notice This is for claiming simple vesting.
    /// @param _poolId : poolId from which pool user want to withdraw.
    /// @notice Secured by nonReentrant
    function claim(uint256 _poolId) external nonReentrant {
        uint256 transferAble = claimable(_poolId, _msgSender());
        UserInfo storage info = userInfo[_poolId][_msgSender()];
        require(transferAble > 0, "IIronVest : Invalid TransferAble");
        IERC20Upgradeable(_poolInfo[_poolId].tokenAddress).safeTransfer(
            _msgSender(),
            transferAble
        );
        uint256 claimed = (info.claimedAmount + transferAble);
        uint256 remainingToBeClaimable = info.allocation - claimed;
        info.claimedAmount = claimed;
        info.remainingToBeClaimable = remainingToBeClaimable;
        info.lastWithdrawal = block.timestamp;
        emit Claim(
            _poolId,
            transferAble,
            _msgSender(),
            remainingToBeClaimable
        );
    }

    /// @dev Only callable by vester.
    /// @param _poolName : Pool name is supposed to be any string.
    /// @param _vestingEndTime : Vesting time is tenure in which token will be released.
    /// @param _cliffVestingEndTime : cliff vesting time is the end time for releasing cliff tokens.
    /// @param _cliffPeriodEndTime : cliff period is a period in which token will be locked.
    /// @param _tokenAddress : Token address related to the vested token.
    /// @param _cliffPercentage10000 : cliff percentage defines how may percentage should be allocated to cliff tokens.
    /// @param _usersAddresses : Users addresses whom the vester want to allocate tokens and it is an array.
    /// @param _usersAlloc : Users allocation of tokens with respect to address.
    /// @param _signature : Signature of the signed by signer.
    /// @param _keyHash : Specific keyhash value formed to stop replay.
    /// @notice Create a new vesting with cliff.
    function addCliffVesting(
        string memory _poolName,
        uint256 _vestingEndTime,
        uint256 _cliffVestingEndTime,
        uint256 _cliffPeriodEndTime,
        address _tokenAddress,
        uint256 _cliffPercentage10000,
        address[] memory _usersAddresses,
        uint256[] memory _usersAlloc,
        bytes memory _signature,
        bytes memory _keyHash
    ) external onlyVester nonReentrant {
        VestingCheck.preAddCliffVesting(
            _vestingEndTime,
            _cliffVestingEndTime,
            _cliffPeriodEndTime,
            _cliffPercentage10000,
            _usersAddresses,
            _usersAlloc
        );
        require(
            signatureVerification(
                _signature,
                _poolName,
                _tokenAddress,
                _keyHash
            ) == signer,
            "Signer : Invalid signer"
        );
        usedHashes[
            VestingCheck.messageHash(_poolName, _tokenAddress, _keyHash)
        ] = true;
        uint256 totalVesting;
        for (uint256 i = 0; i < _usersAddresses.length; i++) {
            uint256 cliffAlloc = (_usersAlloc[i] * _cliffPercentage10000) /
                10000;
            totalVesting += _usersAlloc[i];
            uint256 nonCliffRemainingTobeclaimable = _usersAlloc[i] -
                cliffAlloc;
            userCliffInfo[vestingPoolSize][_usersAddresses[i]] = UserCliffInfo(
                _usersAlloc[i],
                cliffAlloc,
                0,
                _cliffPeriodEndTime,
                cliffAlloc,
                (cliffAlloc) / (_cliffVestingEndTime - _cliffPeriodEndTime),
                _cliffPeriodEndTime,
                false,
                address(0x00)
            );
            userNonCliffInfo[vestingPoolSize][
                _usersAddresses[i]
            ] = UserNonCliffInfo(
                _usersAlloc[i],
                nonCliffRemainingTobeclaimable,
                0,
                _cliffPeriodEndTime,
                nonCliffRemainingTobeclaimable,
                (_usersAlloc[i] - (cliffAlloc)) /
                    (_vestingEndTime - _cliffPeriodEndTime),
                _cliffPeriodEndTime,
                false,
                address(0x00)
            );
        }
        uint256 nonCliffVestingPeriod = _vestingEndTime - _cliffPeriodEndTime;
        _cliffPoolInfo[vestingPoolSize] = CliffPoolInfo(
            _poolName,
            block.timestamp,
            _vestingEndTime,
            _cliffVestingEndTime,
            nonCliffVestingPeriod,
            _cliffPeriodEndTime,
            _tokenAddress,
            totalVesting,
            _cliffPercentage10000,
            _usersAddresses,
            _usersAlloc
        );
        IERC20Upgradeable(_tokenAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            totalVesting
        );
        cliff[vestingPoolSize] = true;
        _totalVestedTokens[_tokenAddress] += totalVesting;
        emit CliffAddVesting(
            _msgSender(),
            vestingPoolSize,
            _poolName,
            _vestingEndTime,
            _cliffVestingEndTime,
            _cliffPeriodEndTime,
            _tokenAddress,
            totalVesting,
            _usersAddresses,
            _usersAlloc
        );
        vestingPoolSize = vestingPoolSize + 1;
    }

    /// @dev Only callable by owner.
    /// @param _poolId : On which pool admin want to update user address.
    /// @param _deprecatedAddress : Old address that need to be updated.
    /// @param _updatedAddress : New address that gonna replace old address.
    /// @notice This function is useful whenever a person lose their address which has pool allocation.
    /// @notice If else block will specify if the pool ID is related to cliff vesting or simple vesting.
    function updateBeneficiaryAddress(
        uint256 _poolId,
        address _deprecatedAddress,
        address _updatedAddress
    ) external virtual onlyOwner nonReentrant {
        VestingCheck.preUpdateBeneficiaryAddress(
            _poolId,
            _deprecatedAddress,
            _updatedAddress,
            vestingPoolSize
        );
        bool isCliff = cliff[_poolId];
        if (isCliff) {
            CliffPoolInfo storage pool = _cliffPoolInfo[_poolId];
            UserCliffInfo storage cliffInfo = userCliffInfo[_poolId][
                _deprecatedAddress
            ];
            UserNonCliffInfo storage nonCliffInfo = userNonCliffInfo[_poolId][
                _deprecatedAddress
            ];
            require(
                nonCliffInfo.allocation > 0,
                "Allocation : This address doesn't have allocation in this pool"
            );
            userNonCliffInfo[_poolId][_updatedAddress] = UserNonCliffInfo(
                nonCliffInfo.allocation,
                nonCliffInfo.nonCliffAlloc,
                nonCliffInfo.claimedAmnt,
                nonCliffInfo.tokensReleaseTime,
                nonCliffInfo.remainingToBeClaimableNonCliff,
                nonCliffInfo.nonCliffReleaseRatePerSec,
                nonCliffInfo.nonCliffLastWithdrawal,
                false,
                address(0x00)
            );
            userCliffInfo[_poolId][_updatedAddress] = UserCliffInfo(
                cliffInfo.allocation,
                cliffInfo.cliffAlloc,
                cliffInfo.claimedAmnt,
                cliffInfo.tokensReleaseTime,
                cliffInfo.remainingToBeClaimableCliff,
                cliffInfo.cliffReleaseRatePerSec,
                cliffInfo.cliffLastWithdrawal,
                false,
                address(0x00)
            );
            delete cliffInfo.allocation;
            cliffInfo.updatedAddress = _updatedAddress;
            cliffInfo.deprecated = true;
            delete nonCliffInfo.allocation;
            nonCliffInfo.updatedAddress = _updatedAddress;
            nonCliffInfo.deprecated = true;
            pool.usersAddresses.push(_updatedAddress);
            pool.usersAlloc.push(cliffInfo.allocation);
        } else {
            PoolInfo storage pool = _poolInfo[_poolId];
            UserInfo storage info = userInfo[_poolId][_deprecatedAddress];
            require(
                info.allocation > 0,
                "Allocation : This address doesn't have allocation in this pool"
            );
            userInfo[_poolId][_updatedAddress] = UserInfo(
                info.allocation,
                info.claimedAmount,
                info.remainingToBeClaimable,
                info.lastWithdrawal,
                info.releaseRatePerSec,
                false,
                address(0x00)
            );
            delete info.allocation;
            info.updatedAddress = _updatedAddress;
            info.deprecated = true;
            pool.usersAddresses.push(_updatedAddress);
            pool.usersAlloc.push(info.allocation);
        }
        deprecatedAddressOf[_updatedAddress] = _deprecatedAddress;
        emit UpdateBeneficiaryWithdrawalAddress(
            _poolId,
            _deprecatedAddress,
            _updatedAddress,
            isCliff
        );
    }

    /// @dev User must have allocation in the pool.
    /// @notice This is for claiming cliff vesting.
    /// @notice should be called if need to claim cliff amount.
    /// @param _poolId : Pool Id from which pool user want to withdraw.
    /// @notice Secured by nonReentrant.
    function claimCliff(uint256 _poolId) external nonReentrant {
        UserCliffInfo storage info = userCliffInfo[_poolId][_msgSender()];
        require(
            _cliffPoolInfo[_poolId].cliffPeriodEndTime < block.timestamp,
            "IIronVest : Cliff Period Is Not Over Yet"
        );

        uint256 transferAble = cliffClaimable(_poolId, _msgSender());
        require(transferAble > 0, "IIronVest : Invalid TransferAble");
        IERC20Upgradeable(_cliffPoolInfo[_poolId].tokenAddress).safeTransfer(
            _msgSender(),
            transferAble
        );
        uint256 claimed = transferAble + info.claimedAmnt;
        uint256 remainingTobeClaimable = info.cliffAlloc - claimed;
        info.claimedAmnt = claimed;
        info.remainingToBeClaimableCliff = remainingTobeClaimable;
        info.cliffLastWithdrawal = block.timestamp;

        emit CliffClaim(
            _poolId,
            transferAble,
            _msgSender(),
            remainingTobeClaimable
        );
    }

    /// @dev User must have allocation in the pool.
    /// @notice This is for claiming cliff vesting.
    /// @notice should be called if need to claim non cliff amount.
    /// @param _poolId : Pool Id from which pool user want to withdraw.
    /// @notice Secured by nonReentrant.
    function claimNonCliff(uint256 _poolId) external nonReentrant {
        UserNonCliffInfo storage info = userNonCliffInfo[_poolId][_msgSender()];
        require(
            _cliffPoolInfo[_poolId].cliffPeriodEndTime < block.timestamp,
            "IIronVest : Cliff Period Is Not Over Yet"
        );

        uint256 transferAble = nonCliffClaimable(_poolId, _msgSender());
        uint256 claimed = transferAble + info.claimedAmnt;
        require(transferAble > 0, "IIronVest : Invalid TransferAble");
        IERC20Upgradeable(_cliffPoolInfo[_poolId].tokenAddress).safeTransfer(
            _msgSender(),
            transferAble
        );
        uint256 remainingTobeClaimable = info.nonCliffAlloc - claimed;
        info.claimedAmnt = claimed;
        info.remainingToBeClaimableNonCliff = remainingTobeClaimable;
        info.nonCliffLastWithdrawal = block.timestamp;
        emit NonCliffClaim(
            _poolId,
            transferAble,
            _msgSender(),
            remainingTobeClaimable
        );
    }

    /// @dev this function use to withdraw tokens that send to the contract mistakenly
    /// @param _token : Token address that is required to withdraw from contract.
    /// @param _amount : How much tokens need to withdraw.
    function emergencyWithdraw(IERC20Upgradeable _token, uint256 _amount)
        external
        onlyOwner
    {
        IERC20Upgradeable(_token).safeTransfer(_msgSender(), _amount);
    }

    /// @dev Function is called by a default admin.
    /// @param _signer : An address whom admin want to be a signer.
    function setSigner(address _signer) external onlyOwner {
        require(
            _signer != address(0x00),
            "Invalid : Signer Address Is Invalid"
        );
        signer = _signer;
    }

    /// @dev Function is called by a default admin.
    /// @param _vestingPreCheck : Reset ironvest pre check address.
    function setPreCheck(IronVestPreCheck _vestingPreCheck) external onlyOwner {
        require(address(_vestingPreCheck) !=address(0x00), "Invalid Address");
        VestingCheck = _vestingPreCheck;
    }

    /// @dev As we are using poolId as unique ID which is supposed to return pool info i.e
    /// _poolInfo and _cliffPoolInfo but it unique for the contract level this function will
    /// return the values from where this poolId relate to.
    /// @param _poolId : Every Pool has a unique Id.
    /// @return isCliff : If this Id relate to the cliffPool or note?
    /// @return poolName : PoolName If exist.
    /// @return startTime : When does this pool initialized .
    /// @return vestingEndTime : Vesting End Time of this Pool.
    /// @return cliffVestingEndTime : CliffVestingEndTime If exist and if also a cliffPool.
    /// @return nonCliffVestingPeriod : Non CliffVesting Period If exist and also a cliffPool.
    /// @return cliffPeriodEndTime : Cliff Period End Time If exist and also a cliffPool.
    /// @return tokenAddress :  Vested token address If exist.
    /// @return totalVestedTokens : total Vested Tokens If exist.
    /// @return cliffLockPercentage : CliffLockPercentage If exist and also a cliffPool.
    function poolInformation(uint256 _poolId)
        external
        view
        returns (
            bool isCliff,
            string memory poolName,
            uint256 startTime,
            uint256 vestingEndTime,
            uint256 cliffVestingEndTime,
            uint256 nonCliffVestingPeriod,
            uint256 cliffPeriodEndTime,
            address tokenAddress,
            uint256 totalVestedTokens,
            uint256 cliffLockPercentage
        )
    {
        bool isCliff = cliff[_poolId];
        if (isCliff) {
            CliffPoolInfo memory info = _cliffPoolInfo[_poolId];
            return (
                isCliff,
                info.poolName,
                info.startTime,
                info.vestingEndTime,
                info.cliffVestingEndTime,
                info.nonCliffVestingPeriod,
                info.cliffPeriodEndTime,
                info.tokenAddress,
                info.totalVestedTokens,
                info.cliffLockPercentage10000
            );
        } else {
            PoolInfo memory info = _poolInfo[_poolId];
            return (
                isCliff,
                info.poolName,
                info.startTime,
                info.vestingEndTime,
                0,
                0,
                0,
                info.tokenAddress,
                info.totalVestedTokens,
                0
            );
        }
    }

    /// @dev This is check claimable for simple vesting.
    /// @param _poolId : Pool Id from which pool user want to check.
    /// @param _user : User address for which user want to check claimables.
    /// @return returning the claimable amount of the user
    function claimable(uint256 _poolId, address _user)
        public
        view
        returns (uint256)
    {
        uint256 claimable;
        UserInfo memory info = userInfo[_poolId][_user];
        require(
            info.allocation > 0,
            "Allocation : You Don't have allocation in this pool"
        );
        if (_poolInfo[_poolId].vestingEndTime <= block.timestamp) {
            claimable = info.remainingToBeClaimable;
        } else
            claimable =
                (block.timestamp - info.lastWithdrawal) *
                info.releaseRatePerSec;

        return (claimable);
    }

    /// @dev This is check claimable for non cliff vesting.
    /// @param _poolId : Pool Id from which pool user want to check.
    /// @param _user : User address for which user want to check claimables.
    /// @return returning the claimable amount of the user from non cliff vesting.
    function nonCliffClaimable(uint256 _poolId, address _user)
        public
        view
        returns (uint256)
    {
        uint256 nonCliffClaimable;
        UserNonCliffInfo memory info = userNonCliffInfo[_poolId][_user];
        require(
            info.allocation > 0,
            "Allocation : You Don't have allocation in this pool"
        );

        if (_cliffPoolInfo[_poolId].cliffPeriodEndTime <= block.timestamp) {
            if (_cliffPoolInfo[_poolId].vestingEndTime >= block.timestamp) {
                nonCliffClaimable =
                    (block.timestamp - info.nonCliffLastWithdrawal) *
                    info.nonCliffReleaseRatePerSec;
            } else nonCliffClaimable = info.remainingToBeClaimableNonCliff;
        }

        return (nonCliffClaimable);
    }

    /// @dev This is check claimable for cliff vesting.
    /// @param _poolId : Pool Id from which pool user want to check.
    /// @param _user : User address for which user want to check claimables.
    /// @return returning the claimable amount of the user from cliff vesting.
    function cliffClaimable(uint256 _poolId, address _user)
        public
        view
        returns (uint256)
    {
        uint256 cliffClaimable;
        UserCliffInfo memory info = userCliffInfo[_poolId][_user];
        require(
            info.allocation > 0,
            "Allocation : You Don't have allocation in this pool"
        );

        if (_cliffPoolInfo[_poolId].cliffPeriodEndTime <= block.timestamp) {
            if (
                _cliffPoolInfo[_poolId].cliffVestingEndTime >= block.timestamp
            ) {
                cliffClaimable =
                    (block.timestamp - info.cliffLastWithdrawal) *
                    info.cliffReleaseRatePerSec;
            } else cliffClaimable = info.remainingToBeClaimableCliff;
        }

        return (cliffClaimable);
    }

    /// @dev For getting signer address from salt and signature.
    /// @param _signature : signature provided signed by signer.
    /// @param _poolName : Pool Name to name a pool.
    /// @param _tokenAddress : tokenAddress of our vested tokesn.
    /// @param _keyHash : keyhash value to stop replay.
    /// @return Address of signer who signed the message hash.
    function signatureVerification(
        bytes memory _signature,
        string memory _poolName,
        address _tokenAddress,
        bytes memory _keyHash
    ) public view returns (address) {
        bytes32 _salt = VestingCheck.messageHash(
            _poolName,
            _tokenAddress,
            _keyHash
        );
        (bytes32 r, bytes32 s, uint8 v) = VestingCheck.splitSignature(
            _signature
        );
        require(!usedHashes[_salt], "Message already used");

        address _user = VestingCheck.verifyMessage(_salt, v, r, s);
        return _user;
    }
    
    /// @dev this function suppose to return unallocated tokens against a token address
    /// @param _tokenAddress : Token address that is required to check from contract.
    function unAllocatedTokens(address _tokenAddress)
        public
        view
        returns (uint256 unAllocatedTokens)
    {
        return
            IERC20Upgradeable(_tokenAddress).balanceOf(address(this)) -
            _totalVestedTokens[_tokenAddress];
    }
}
