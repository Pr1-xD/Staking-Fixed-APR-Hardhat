
// SPDX-License-Identifier: MIT


import "./Context.sol";
import "./Reentrancy.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./Address.sol";


pragma solidity >0.6.0;

contract StakingContract is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {                                   //Stores All User Info
        uint256 balance;                                //User Balance
        uint256 lastClaimed;                            //Last Claim Timestamp 
        uint256 pendingRewards;                         //Pending Rewards from withdrawn amount
        mapping(uint256 => uint256) depositAmount;      //index => amount
        mapping(uint256 => uint256) depositTimestamp;   //index => timestamp
        uint256 first;                                  //first index for deposit timestamp queue
        uint256 last;                                   //last index for deposit timestamp queue
    }

    uint256 poolBalance;
    uint256 maxCap = uint256(-1);
    uint256 rewardsAmount;
    uint256 lockupDuration;

    uint256 startBlock;                                 //Staking Start Timestamp

   
    IERC20 public stakingToken;                         // ERC20 Staking Token Address
    address public feeRecipient;                        
    uint256 public withdrawalFee;                       // Fee * 100 Example: 2% = 200
    uint256 public constant MAX_FEE = 10000;
    uint256 public constant MAX_REWARD_RATE = 10000;
    uint256 public minDepositAmount = 1;
    uint256 public maxDepositAmount = uint256(-1);
    uint256 public maxUserBalance = uint256(-1);


   mapping(address => UserInfo) public userInfo;

   uint256[] public rewardRate;                         //Array of APR values
   uint256[] public rewardRateTimestamp;                //Array of APR change timestamps

    event Deposit(address user, uint256 amount);
    event Withdraw(address user, uint256 amount);
    event Claim(address user, uint256 amount);

    /**
     * @dev Sets value for staking token address, lockup duration(in days),
     * address of fee reciepient, reward rate (for 2% enter 200) and maximum
     * user balance 
     *
     * Withdrawal Fee is set to zero by default
     *
     * To start staking, use startStaking function
     *
     */
    constructor(address _stakingToken,uint256 _lockupDuration,address _feeRecipient, uint256 _rewardRate, uint256 _maxUserBalance) {
        rewardRate.push(0);
        rewardRateTimestamp.push(0);     
        stakingToken = IERC20(_stakingToken);
        feeRecipient = _feeRecipient;
        lockupDuration=_lockupDuration;
        rewardRate.push(_rewardRate);
        maxUserBalance=_maxUserBalance;
    }
    
    /**
     * @dev Function to start staking allowing users to deposit
     *
     * Start block is set to current block timestamp
     *
     */
    function startStaking() external onlyOwner {
    require(startBlock==0,"Staking already started");    
    startBlock=block.timestamp;
    rewardRateTimestamp.push(startBlock);
    }

    /**
     * @dev Sets value for lockup duration for each deposit.
     * Enter value in days
     * Withdrawals before lockupDuration ends will need to pay withdrawal fee.
     *
     */
    function setLockupDuration(uint256 _lockupDuration) external onlyOwner {
        lockupDuration = _lockupDuration;
    }

    /**
     * @dev Sets maximum cap for pool balance.
     * 
     * Set to maximum integer value by default
     *
     */
    function setMaxCap(uint256 _cap) external onlyOwner {
        maxCap = _cap;
    }

    /**
     * @dev Returns value of total pool balance.
     * 
     * Only counts the total deposited value.
     */
    function balance() public view returns (uint256) {              
        return poolBalance;
    }

    /**
     * @dev Returns value of current reward rate of the pool
     * 
     * 200 = 2% APR
     * 
     * Can be changed by owner using setRewardRate
     * 
     */
    function currentRewardRate() public view returns (uint256) {
        return rewardRate[rewardRate.length-1];
    }

    /**
     * @dev Returns current total deposited value by a user.
     */
    function balanceOf(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        return user.balance;
    }

    /**
     * @dev Function to deposit tokens into the pool
     * 
     * Requirements:
     * 
     * Can only be done when staking has started
     * Deposit amount has to be greater than minimum deposit amount
     * Deposit amount has to be less than maximum deposit amount
     * 
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused{     
        require(startBlock!=0, "Staking has not started");
        require(amount >= minDepositAmount, "Less than minimum deposit amount");
        UserInfo storage user = userInfo[msg.sender];
        require (user.balance.add(amount) <= maxUserBalance, "Exceeded maximum balance per user");
        require (poolBalance.add(amount) <= maxCap, "Exceeded pool cap");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        user.balance = user.balance.add(amount);
        addDeposit(msg.sender,amount);
        poolBalance = poolBalance.add(amount);

        emit Deposit(msg.sender, amount);
    }

    /**
     * @dev Function to withdraw deposited amount from the pool
     * 
     * Amount that has not completed its lockupDuration will be 
     * taxed based on withdrawalFee
     * 
     * All the rewards accumulated for the withdrawn amount will
     * be add to user's pendingRewards 
     * 
     */
    function withdraw(uint256 amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(amount > 0 && user.balance >= amount, "Invalid amount");

        uint256 feeAmount = 0;
        uint256 index = user.first;
        uint256 secondsStaked = 0;
        uint256 depositTotal = 0;
        uint256 remainingAmount = amount;

        while(depositTotal < amount){

            if(user.depositAmount[index] > remainingAmount){            
                user.depositAmount[index]=user.depositAmount[index].sub(remainingAmount);
                depositTotal = depositTotal.add(remainingAmount);
                
                uint256 rewardCalculationTime = 0;
                uint256 rewardsAccumulated = 0;

                //Calculate rewards for withdrawing amount
                if(user.lastClaimed >= user.depositTimestamp[index]) rewardCalculationTime=user.lastClaimed;
                if(user.lastClaimed < user.depositTimestamp[index]) rewardCalculationTime=user.depositTimestamp[index];

                for ( uint256 i = 0; i<rewardRateTimestamp.length-1; i++){
                    if(rewardCalculationTime >= rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardCalculationTime;
                        rewardsAccumulated = rewardsAccumulated + ((remainingAmount * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                    else if(rewardCalculationTime < rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardRateTimestamp[i];
                        rewardsAccumulated = rewardsAccumulated + ((remainingAmount * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                }

                if( rewardCalculationTime >= rewardRateTimestamp[rewardRateTimestamp.length-1]){
                    secondsStaked = block.timestamp - rewardCalculationTime;
                    rewardsAccumulated = rewardsAccumulated + ((remainingAmount * rewardRate[rewardRateTimestamp.length-1] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                }

                user.pendingRewards = user.pendingRewards + rewardsAccumulated;
                
                secondsStaked=block.timestamp - user.depositTimestamp[index];
                if(secondsStaked <= (lockupDuration*86400))
                feeAmount = feeAmount + ((remainingAmount * withdrawalFee) / MAX_FEE);
            }

            else if(user.depositAmount[index] < remainingAmount){
                remainingAmount=remainingAmount.sub(user.depositAmount[index]);   
                depositTotal=depositTotal.add(user.depositAmount[index]);

                //Calculate rewards for withdrawing amount
                uint256 rewardCalculationTime = 0;
                uint256 rewardsAccumulated = 0;
                if(user.lastClaimed >= user.depositTimestamp[index]) rewardCalculationTime=user.lastClaimed;
                if(user.lastClaimed < user.depositTimestamp[index]) rewardCalculationTime=user.depositTimestamp[index];

                for ( uint256 i = 0; i<rewardRateTimestamp.length-1; i++){
                    if(rewardCalculationTime >= rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardCalculationTime;
                        rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                    else if(rewardCalculationTime < rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardRateTimestamp[i];
                        rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                }

                if( rewardCalculationTime >= rewardRateTimestamp[rewardRateTimestamp.length-1]){
                    secondsStaked = block.timestamp - rewardCalculationTime;
                    rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[rewardRateTimestamp.length-1] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                }

                user.pendingRewards = user.pendingRewards + rewardsAccumulated;

                secondsStaked=block.timestamp.sub(user.depositTimestamp[index]);
                if(secondsStaked <= (lockupDuration*86400))
                feeAmount = feeAmount + ((user.depositAmount[index] * withdrawalFee) / MAX_FEE);

                delete user.depositAmount[index];
                delete user.depositTimestamp[index];
                user.first += 1;
            }

            else {
                depositTotal = remainingAmount;

                //Calculate rewards for withdrawing amount
                uint256 rewardCalculationTime = 0;
                uint256 rewardsAccumulated = 0;
                if(user.lastClaimed >= user.depositTimestamp[index]) rewardCalculationTime=user.lastClaimed;
                if(user.lastClaimed < user.depositTimestamp[index]) rewardCalculationTime=user.depositTimestamp[index];

                for ( uint256 i = 0; i<rewardRateTimestamp.length-1; i++){
                    if(rewardCalculationTime >= rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardCalculationTime;
                        rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                    else if(rewardCalculationTime < rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardRateTimestamp[i];
                        rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                }

                if( rewardCalculationTime >= rewardRateTimestamp[rewardRateTimestamp.length-1]){
                    secondsStaked = block.timestamp - rewardCalculationTime;
                    rewardsAccumulated = rewardsAccumulated + ((user.depositAmount[index] * rewardRate[rewardRateTimestamp.length-1] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                }

                user.pendingRewards = user.pendingRewards + rewardsAccumulated;

                secondsStaked=block.timestamp - user.depositTimestamp[index];
                if(secondsStaked <= (lockupDuration*86400))
                feeAmount = feeAmount + ((amount * withdrawalFee) / MAX_FEE);

                delete user.depositAmount[index];
                delete user.depositTimestamp[index];
                user.first += 1;
            }

            index = index + 1;
        }

        if (feeAmount > 0) stakingToken.safeTransfer(feeRecipient, feeAmount);
        stakingToken.safeTransfer(address(msg.sender), amount.sub(feeAmount));
        
        user.balance = user.balance.sub(amount);

        poolBalance = poolBalance.sub(amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Function to withdraw complete deposited amount
     */
    function withdrawAll() external {           
        UserInfo storage user = userInfo[msg.sender];
        withdraw(user.balance);
    }

    /**
     * @dev Returns current claimable rewards for a user
     * 
     * Includes any pending rewards from withdrawn amount
     * 
     * Reward is calculated based on rewardRate
     * 
     * Use Claim function to claim rewards
     */
    function claimable(address _user) public view returns (uint256) {   
        require(startBlock > 0, 'Staking not yet started');
        
        UserInfo storage user = userInfo[_user];
        // require(user.balance > 0, "No staked amount");
        uint256 index = user.first;
        uint256 secondsStaked = 0;
        uint256 amountStaked = 0;
        uint256 totalReward = 0;

        while(index <= user.last){              // Calculates accumulated rewards for deposited amount
            amountStaked = user.depositAmount[index];
            uint256 rewardCalculationTime = 0;
            uint256 rewardsAccumulated = 0;

                if(user.lastClaimed >= user.depositTimestamp[index]) rewardCalculationTime=user.lastClaimed;    //Calculate from last claimed or deposit time, depending on latest value
                if(user.lastClaimed < user.depositTimestamp[index]) rewardCalculationTime=user.depositTimestamp[index];

                for ( uint256 i = 0; i<rewardRateTimestamp.length-1; i++){
                    if(rewardCalculationTime >= rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardCalculationTime;                      
                        rewardsAccumulated = rewardsAccumulated + ((amountStaked * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                    else if(rewardCalculationTime < rewardRateTimestamp[i] && rewardCalculationTime < rewardRateTimestamp[i+1]){
                        secondsStaked =  rewardRateTimestamp[i+1] - rewardRateTimestamp[i];                     
                        rewardsAccumulated = rewardsAccumulated + ((amountStaked * rewardRate[i] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                    }
                }

                if( rewardCalculationTime >= rewardRateTimestamp[rewardRateTimestamp.length-1]){
                    secondsStaked = block.timestamp - rewardCalculationTime;
                    rewardsAccumulated = rewardsAccumulated + ((amountStaked * rewardRate[rewardRateTimestamp.length-1] * secondsStaked) / (86400 * 365 * MAX_REWARD_RATE));
                }

                totalReward = totalReward + rewardsAccumulated;

            index = index + 1;
        }

        return totalReward.add(user.pendingRewards);        
    }

    /**
     * @dev Function to claim current claimable rewards of the sender.
     * 
     * Use Claimable function to check currently accumulated rewards.
     */
    function claim() public nonReentrant {                             
        UserInfo storage user = userInfo[msg.sender];
        uint256 reward = claimable(msg.sender);
        uint256 claimedAmount = safeTransferRewards(msg.sender, reward);
        user.lastClaimed = block.timestamp;
        user.pendingRewards = 0;

        emit Claim(msg.sender, claimedAmount);
    }


    /**
     * @dev Internal function to add deposit value and timestamp to queue.
     */
    function addDeposit(address _user,uint256 amount) internal {        
        UserInfo storage user = userInfo[_user];

        if(user.first == 0)   //initialize
        user.first=1;

        user.last += 1;
        user.depositTimestamp[user.last] = block.timestamp;
        user.depositAmount[user.last] = amount;
    }
    
    /**
     * @dev Internal function to safeTransfer rewards from contract
     */
    function safeTransferRewards(address to, uint256 amount) internal returns (uint256) {
        uint256 _bal = stakingToken.balanceOf(address(this));
        if (amount > _bal) amount = _bal;       //decide between this or error
        stakingToken.safeTransfer(to, amount);
        return amount;
    }
    
    /**
     * @dev Function to set rewardRate for the pool
     * 
     * To set reward rate as 0, use pause function
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        require(_rewardRate>0, "Invalid value");
        rewardRate.push(_rewardRate);
        rewardRateTimestamp.push(block.timestamp);
    }

    /**
     * @dev Function to set minimum deposit amount
     */
    function setMinDepositAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Invalid value");
        minDepositAmount = _amount;
    }

    /**
     * @dev Function to set maximum deposit amount
     */
    function setMaxDepositAmount(uint256 _amount) external onlyOwner {
        require(_amount > minDepositAmount, "Invalid value, should be greater than mininum deposit amount");
        maxDepositAmount = _amount;
    }

    /**
     * @dev Function to set maximum balance per user
     */
    function setMaxUserBalance(uint256 _amount) external onlyOwner {
        require(_amount > minDepositAmount, "Invalid value, should be greater than mininum deposit amount");
        maxUserBalance= _amount;
    }

    /**
     * @dev Function to set withdrawalFee
     *
     * Multiply Rate by 100 for input
     * Use 200 to set withdrawalFee as 2%
     * 
     */
    function setWithdrawalFee(uint256 _fee) external onlyOwner {
        require(_fee < MAX_FEE, "Invalid fee");
        withdrawalFee = _fee;
    }

    /**
     * @dev Set address that recieves all withdrawalFee amount
     */
    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    /**
     * @dev Function to pause the contract
     * 
     * Sets APR to 0%
     * Does not allow new deposits
     * 
     */
    function pause() external onlyOwner {
        rewardRate.push(0);                                 //Sets APR to 0
        rewardRateTimestamp.push(block.timestamp);
        _pause();
    }

    /**
     * @dev Function to unpause the contract
     * 
     * Sets APR to previous APR(before pausing)
     * Deposits are allowed again
     */
    function unpause() external onlyOwner {
        rewardRate.push(rewardRate.length-2);               //Resets to previous APR
        rewardRateTimestamp.push(block.timestamp);
        _unpause();
    }

    /**
     * @dev Emergency function
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        uint256 _bal = IERC20(_token).balanceOf(address(this));
        if (_amount > _bal) _amount = _bal;

        IERC20(_token).safeTransfer(_msgSender(), _amount);
    }
}
