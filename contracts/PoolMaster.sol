pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Admin.sol";

import "./interfaces/IALP.sol";
import "./interfaces/IGGR.sol";

contract PoolMaster is Admin {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        uint256 id;
        uint256 minAmount;
        uint256 ALPperGGR;
        uint256 lockPeriod;
        uint256 allocPoint; //apr bonus
        address acceptedToken;
        uint256 lastRewardBlock;
        uint256 accGGRperShare;
        bool isOpenPool;
    }

    struct UserInfo {
        uint256 amountStaked;
        uint256 lastStakedTime;
        uint256 rewardDebt;
    }

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // GGR tokens created per block.
    uint256 public ggrPerBlock;

    //pool id -> user address -> user info
    mapping(uint256 => mapping(address => UserInfo)) private userInfo;

    //user address -> total ALP amount
    mapping(address => uint256) public totalUserALP;

    PoolInfo[] private pools;

    address public immutable GGR;
    address public immutable ALP;

    event Deposit(address indexed user, uint256 indexed idPool, uint256 amount);
    event Withdraw(
        address indexed user,
        uint256 indexed idPool,
        uint256 amount
    );
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed idPool,
        uint256 amount
    );

    constructor(
        address _ggr,
        address _alp,
        uint256 _ggrPerBlock
    ) {
        GGR = _ggr;
        ALP = _alp;
        ggrPerBlock = _ggrPerBlock;
    }

    function addPool(
        uint256 _ALPperGGR,
        uint64 _lockPeriod,
        uint256 _allocPoint,
        uint256 _minAmount,
        address _acceptedToken
    ) public onlyAdmin {
        totalAllocPoint += _allocPoint;
        pools.push(
            PoolInfo({
                id: pools.length + 1,
                minAmount: _minAmount,
                ALPperGGR: _ALPperGGR,
                lockPeriod: _lockPeriod,
                allocPoint: _allocPoint,
                lastRewardBlock: block.number,
                acceptedToken: _acceptedToken,
                accGGRperShare: 0,
                isOpenPool: true
            })
        );
    }

    function closePool(uint256 _id) public onlyAdmin {
        require(pools[_id].isOpenPool, "closePool: Pool is already closed");
        pools[_id].isOpenPool = false;
    }

    function updateAllocPoint(uint256 _id, uint256 _allocPoint)
        public
        onlyAdmin
    {
        totalAllocPoint = totalAllocPoint - pools[_id].allocPoint + _allocPoint;
        pools[_id].allocPoint = _allocPoint;
    }

    function updateLockPeriod(uint256 _id, uint64 _lockPeriod)
        public
        onlyAdmin
    {
        pools[_id].lockPeriod = _lockPeriod;
    }

    function updateALPperGGR(uint256 _id, uint256 _ALPperGGR) public onlyAdmin {
        pools[_id].ALPperGGR = _ALPperGGR;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) private {
        PoolInfo storage pool = pools[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 acceptedTokenSupply = IERC20(pool.acceptedToken).balanceOf(
            address(this)
        );
        if (acceptedTokenSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - pool.lastRewardBlock;

        uint256 reward = (multiplier * ggrPerBlock * pool.allocPoint) /
            totalAllocPoint;

        IGGR(GGR).mint(address(this), reward);
        pool.accGGRperShare =
            pool.accGGRperShare +
            (reward * 1e12) /
            acceptedTokenSupply;
        pool.lastRewardBlock = block.number;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public onlyAdmin {
        uint256 length = pools.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    //Deposit tokens to PoolMaster
    function deposit(uint256 _idPool, uint256 _amount) public {
        PoolInfo storage pool = pools[_idPool]; //TODO проверить обновление после изменения
        UserInfo storage user = userInfo[_idPool][msg.sender];
        require(pool.isOpenPool, "Deposit: Pool is closed");
        require(
            _amount + user.amountStaked >= pool.minAmount,
            "Deposit: insufficient amount"
        );
        updatePool(_idPool);
        if (user.amountStaked > 0) {
            uint256 pending = (user.amountStaked * pool.accGGRperShare) /
                1e12 -
                user.rewardDebt;
            safeGGRTransfer(msg.sender, pending);
        }

        IERC20(pool.acceptedToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        IALP(ALP).mint(msg.sender, _amount * pools[_idPool].ALPperGGR);

        user.amountStaked = user.amountStaked + _amount;
        user.lastStakedTime = block.timestamp;
        totalUserALP[msg.sender] += _amount * pool.ALPperGGR;
        user.rewardDebt = (user.amountStaked * pool.accGGRperShare) / 1e12;

        emit Deposit(msg.sender, _idPool, _amount);
    }

    function withdraw(uint256 _idPool) public {
        PoolInfo storage pool = pools[_idPool];
        UserInfo storage user = userInfo[_idPool][msg.sender];

        require(
            user.lastStakedTime + pool.lockPeriod < block.timestamp,
            "Withdraw: funds are still locked"
        );
        updatePool(_idPool);
        uint256 pending = (user.amountStaked * pool.accGGRperShare) /
            1e12 -
            user.rewardDebt;
        safeGGRTransfer(msg.sender, pending);
        IERC20(pool.acceptedToken).safeTransfer(msg.sender, user.amountStaked);
        IALP(ALP).burn(msg.sender, user.amountStaked * pool.ALPperGGR);
        totalUserALP[msg.sender] =
            totalUserALP[msg.sender] -
            user.amountStaked *
            pool.ALPperGGR;
        emit Withdraw(msg.sender, _idPool, user.amountStaked);
        user.amountStaked = 0;
    }

    function emergencyWithdraw(uint256 _idPool) public {
        PoolInfo storage pool = pools[_idPool];
        UserInfo storage user = userInfo[_idPool][msg.sender];

        IERC20(pool.acceptedToken).safeTransfer(
            address(msg.sender),
            user.amountStaked
        );
        IALP(ALP).burn(msg.sender, user.amountStaked * pool.ALPperGGR);

        totalUserALP[msg.sender] =
            totalUserALP[msg.sender] -
            user.amountStaked *
            pool.ALPperGGR;
        emit EmergencyWithdraw(msg.sender, _idPool, user.amountStaked);
        user.rewardDebt = 0;
        user.amountStaked = 0;
    }

    // Safe GGR transfer function, just in case if rounding error causes pool to not have enough GGRs.
    function safeGGRTransfer(address _to, uint256 _amount) internal {
        uint256 GGRBal = IERC20(GGR).balanceOf(address(this));
        if (_amount > GGRBal) {
            IERC20(GGR).transfer(_to, GGRBal);
        } else {
            IERC20(GGR).transfer(_to, _amount);
        }
    }

    function poolsLength() external view returns (uint256) {
        return pools.length;
    }

    function getPool(uint256 poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    function getUserInfo(uint256 poolId, address userAddress)
        external
        view
        returns (UserInfo memory)
    {
        return userInfo[poolId][userAddress];
    }

    function getTotalAllocPoint() external view returns (uint256) {
        return totalAllocPoint;
    }

    function getTotalUserALP(address userAddress)
        external
        view
        returns (uint256)
    {
        return totalUserALP[userAddress];
    }
}
