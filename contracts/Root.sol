pragma solidity ^0.8.0;

import "./Admin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "hardhat/console.sol";

contract Root is Admin {
    using SafeERC20 for IERC20;

    enum State {
        upcoming,
        redeem,
        fcfs,
        claim,
        ended
    }

    event CreateProject(uint256 indexed id, uint256 indexed offchainId);
    event StartIDO(uint256 indexed id);
    event WithdrawProject(uint256 indexed id);
    event Redeemed(uint256 indexed id, address indexed investor);

    struct Project {
        uint256 id;
        ProjectProps props;
        address[] investors;
        uint256[] amounts;
        uint256[] redeemed;
        uint256[] claimed;
        uint256 totalInvested;
        uint256 availableBalance;
        State state;
    }

    struct ProjectProps {
        IERC20 token;
        IERC20 claimToken;
        uint256 price;
        uint256[] claimDates;
        uint256[] claimPercent;
    }

    // Mapping investor address to project count
    mapping(address => uint256) private _investorsBalances;
    // Mapping from investor to list of projects
    mapping(address => mapping(uint256 => uint256)) private _investorProjects;
    // Mapping from project ID to index of the investor projects list
    mapping(uint256 => uint256) private _investorProjectsIndex;
    // Mapping from investor address and projectId to investor index from project
    mapping(address => mapping(uint256 => uint256))
        private _investorIndexOfProject;
    // Array with all project ids, used for enumeration
    uint256[] private _allProjects;
    // Mapping project id to project
    mapping(uint256 => Project) internal _projects;

    uint256[] private _tempRedeemed;

    function createProject(
        ProjectProps memory props,
        address[] memory investors,
        uint256[] memory amounts,
        uint256 offchainId
    ) public onlyAdmin {
        require(
            investors.length == amounts.length,
            "createProject: arr length not eq"
        );
        require(
            props.claimDates.length == props.claimPercent.length &&
                props.price > 0 &&
                props.token != IERC20(address(0)) &&
                props.claimToken != IERC20(address(0)),
            "createProject: invalid props"
        );
        delete _tempRedeemed;
        uint256 nextProjectId = _allProjects.length + 1;
        _allProjects.push(nextProjectId);
        uint256 totalAmount;
        for (uint256 i = 0; i < investors.length; i++) {
            totalAmount += amounts[i];
            address investor = investors[i];
            _addProjectToInvestorEnumeration(investor, nextProjectId, i);
            _tempRedeemed.push(0);
        }
        _projects[nextProjectId] = Project(
            nextProjectId,
            props,
            investors,
            amounts,
            _tempRedeemed,
            _tempRedeemed,
            0,
            totalAmount,
            State.upcoming
        );
        emit CreateProject(nextProjectId, offchainId);
    }

    function startIDO(uint256 projectId) public onlyAdmin {
        Project storage project = _projects[projectId];
        require(project.state == State.upcoming, "startRedeem: bad state");
        project.state = State.redeem;
        emit StartIDO(projectId);
    }

    function changeProject(
        uint256 projectId,
        uint256[] memory removedInvestorIndexes,
        int256[] memory indexes,
        address[] memory investorAddrs,
        uint256[] memory amounts
    ) public onlyAdmin {
        require(
            investorAddrs.length == amounts.length &&
                amounts.length == indexes.length,
            "addInvestors: invalid arguments"
        );
        Project storage project = _projects[projectId];
        for (uint256 i; i < indexes.length; i++) {
            require(indexes[i] >= -1, "changeProject: invalid index");
            if (indexes[i] == -1) {
                require(amounts[i] > 0, "changeProject: amounts[i] == 0");
                _addInvestor(project, investorAddrs[i], amounts[i], false);
                project.availableBalance += amounts[i];
            } else {
                require(
                    investorAddrs[i] != address(0) || amounts[i] != 0,
                    "changeProject: investorAddrs[i] and amounts[i] is null"
                );
                _changeInvestorAmount(project, uint256(indexes[i]), amounts[i]);
                _changeInvestorAddr(
                    project,
                    uint256(indexes[i]),
                    investorAddrs[i]
                );
            }
        }
        if (removedInvestorIndexes.length > 0) {
            _removeInvestors(project, removedInvestorIndexes);
        }
    }

    function redeemAllocation(uint256 projectId, uint256 amount) public {
        Project storage project = _projects[projectId];
        require(
            project.state == State.redeem || project.state == State.fcfs,
            "redeemAllocation: bad state"
        );
        uint256 investorIndex = _investorIndexOfProject[msg.sender][projectId];
        bool isAllocated = project.investors[investorIndex] == msg.sender;
        if (project.state == State.redeem) {
            require(isAllocated, "redeemAllocation: not allocated");
            amount =
                project.amounts[investorIndex] -
                project.redeemed[investorIndex];
        } else {
            require(
                amount <= project.availableBalance && amount > 0,
                "redeemAllocation: invalid amount"
            );
        }
        IERC20(project.props.token).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!isAllocated) {
            _addInvestor(project, msg.sender, amount, true);
        } else {
            project.redeemed[investorIndex] += amount;
            project.amounts[investorIndex] = project.redeemed[investorIndex];
        }
        project.totalInvested += amount;
        project.availableBalance -= amount;
        emit Redeemed(projectId, msg.sender);
    }

    function startFCFS(uint256 projectId) public onlyAdmin {
        Project storage project = _projects[projectId];
        require(project.state == State.redeem, "startFCFS: bad state");
        project.state = State.fcfs;
    }

    function _addInvestor(
        Project storage project,
        address investor,
        uint256 amount,
        bool isFCFS
    ) private {
        _addProjectToInvestorEnumeration(
            investor,
            project.id,
            project.investors.length
        );

        project.investors.push(investor);
        project.amounts.push(amount);
        project.redeemed.push(isFCFS ? amount : 0);
        project.claimed.push(0);
    }

    function _addProjectToInvestorEnumeration(
        address investor,
        uint256 projectId,
        uint256 index
    ) private {
        require(
            isAdmin(investor) == false && owner() != investor,
            "investor cannot be an administrator or owner"
        );
        _investorIndexOfProject[investor][projectId] = index;
        uint256 length = balanceOfInvestor(investor);
        _investorProjects[investor][length] = projectId;
        _investorProjectsIndex[projectId] = length;
        _investorsBalances[investor] += 1;
    }

    function _removeInvestors(
        Project storage project,
        uint256[] memory investorIndexes
    ) private {
        for (uint256 i; i < investorIndexes.length; i++) {
            _removeInvestor(project, investorIndexes[i]);
        }
    }

    function _removeInvestor(Project storage project, uint256 investorIndex)
        private
    {
        address investor = project.investors[investorIndex];
        project.availableBalance -= (project.amounts[investorIndex] -
            project.redeemed[investorIndex]);
        if (project.redeemed[investorIndex] > 0) {
            project.totalInvested -= project.redeemed[investorIndex];
        }
        _removeProjectFromInvestorEnumeration(investor, project.id);
        uint256 lastInvestorIndex = project.investors.length - 1;
        if (lastInvestorIndex != investorIndex) {
            project.investors[investorIndex] = project.investors[
                lastInvestorIndex
            ];
            project.amounts[investorIndex] = project.amounts[lastInvestorIndex];
            project.redeemed[investorIndex] = project.redeemed[
                lastInvestorIndex
            ];
            project.claimed[investorIndex] = project.claimed[lastInvestorIndex];
            _investorIndexOfProject[project.investors[investorIndex]][
                project.id
            ] = investorIndex;
        }
        project.investors.pop();
        project.amounts.pop();
        project.redeemed.pop();
        project.claimed.pop();
    }

    function _removeProjectFromInvestorEnumeration(
        address investor,
        uint256 projectId
    ) private {
        delete _investorIndexOfProject[investor][projectId];
        uint256 lastProjectIndex = balanceOfInvestor(investor) - 1;
        uint256 projectIndex = _investorProjectsIndex[projectId];
        if (projectIndex != lastProjectIndex) {
            uint256 lastProjectId = _investorProjects[investor][
                lastProjectIndex
            ];
            _investorProjects[investor][projectIndex] = lastProjectIndex;
            _investorProjectsIndex[lastProjectId] = projectIndex;
        }
        delete _investorProjectsIndex[projectId];
        delete _investorProjects[investor][lastProjectIndex];
        _investorsBalances[investor] -= 1;
    }

    function _changeInvestorAddr(
        Project storage project,
        uint256 investorIndex,
        address newAddr
    ) private {
        if (project.investors[investorIndex] != newAddr) {
            _removeProjectFromInvestorEnumeration(
                project.investors[investorIndex],
                project.id
            );
            _addProjectToInvestorEnumeration(
                newAddr,
                project.id,
                investorIndex
            );
            project.investors[investorIndex] = newAddr;
        }
    }

    function _changeInvestorAmount(
        Project storage project,
        uint256 investorIndex,
        uint256 newAmount
    ) private {
        require(
            newAmount >= project.redeemed[investorIndex],
            "_changeInvestorAmount: amount < redeemed"
        );
        uint256 oldAmount = project.amounts[investorIndex];
        if (oldAmount != newAmount) {
            _changeProjectAvailableBalance(oldAmount, newAmount, project);
            project.amounts[investorIndex] = newAmount;
        }
    }

    function _changeProjectAvailableBalance(
        uint256 oldAmount,
        uint256 newAmount,
        Project storage project
    ) private {
        if (oldAmount != newAmount) {
            if (newAmount > oldAmount) {
                project.availableBalance += (newAmount - oldAmount);
            } else {
                project.availableBalance -= (oldAmount - newAmount);
            }
        }
    }

    function withdrawProject(uint256 projectId, address to) public onlyAdmin {
        Project storage project = _projects[projectId];
        require(
            project.totalInvested > 0,
            "withdrawProject: you cannot withdraw 0"
        );
        require(
            project.state == State.redeem || project.state == State.fcfs,
            "withdrawProject: tokens were withdrawn"
        );
        project.props.token.safeTransfer(to, project.totalInvested);
        project.state = State.claim;
        emit WithdrawProject(projectId);
    }

    function addTotalAmount(uint256 projectId, uint256 addCount)
        public
        onlyAdmin
    {
        Project storage project = _projects[projectId];
        require(
            project.state == State.fcfs,
            "changeTotalAmount: state is not fcfs"
        );
        project.availableBalance += addCount;
    }

    function subTotalAmount(uint256 projectId, uint256 subCount)
        public
        onlyAdmin
    {
        Project storage project = _projects[projectId];
        require(
            project.availableBalance >= subCount,
            "subTotalAmount: subCount > availableBalance"
        );
        require(
            project.state == State.fcfs,
            "changeTotalAmount: state is not fcfs"
        );
        project.availableBalance -= subCount;
    }

    function claimProject(uint256 projectId) public {
        Project storage project = _projects[projectId];
        uint256 investorIndex = _investorIndexOfProject[msg.sender][projectId];
        require(
            project.investors[investorIndex] == msg.sender,
            "claimProject: wrong caller"
        );
        require(
            project.state == State.claim || project.state == State.ended,
            "claimIDO: bad state"
        );
        for (
            uint256 i = project.claimed[investorIndex];
            i < project.props.claimDates.length;
            i++
        ) {
            if (block.timestamp >= project.props.claimDates[i]) {
                project.props.claimToken.safeTransfer(
                    msg.sender,
                    (((project.redeemed[investorIndex] / project.props.price) *
                        1e18) / 100) * project.props.claimPercent[i]
                );
                project.claimed[investorIndex] += 1;
            } else {
                return;
            }
        }
        if (
            block.timestamp >=
            project.props.claimDates[project.props.claimDates.length - 1] &&
            project.state != State.ended
        ) {
            project.state = State.ended;
        }
    }

    function balanceOfInvestor(address investor) public view returns (uint256) {
        return _investorsBalances[investor];
    }

    function projectOfInvestorByIndex(address investor, uint256 index)
        public
        view
        returns (uint256)
    {
        return _investorProjects[investor][index];
    }

    function projectById(uint256 projectId)
        public
        view
        returns (Project memory)
    {
        return _projects[projectId];
    }

    function totalSupply() public view returns (uint256) {
        return _allProjects.length;
    }

    function investorIndexFromProject(address investorAddr, uint256 projectId)
        public
        view
        returns (uint256)
    {
        return _investorIndexOfProject[investorAddr][projectId];
    }

    function withdraw(
        IERC20 token,
        address to,
        uint256 amount
    ) public onlyOwner {
        if (amount == 0) {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(to, amount);
    }

    function distribute(
        IERC20 token,
        address from,
        address[] memory investors,
        uint256[] memory amounts
    ) public onlyOwner {
        require(investors.length == amounts.length, "arr length not eq");
        for (uint256 i = 0; i < investors.length; i++) {
            token.safeTransferFrom(from, investors[i], amounts[i]);
        }
    }
}
