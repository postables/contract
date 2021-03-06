pragma solidity ^0.4.23;

import "./UTXORedeemableToken.sol";

/* solium-disable security/no-block-members */


contract StakeableToken is UTXORedeemableToken {

    event Mint(address indexed _address, uint _reward);

    uint256 totalBTCCirculationAtFork;

    uint256 stakedCoins;

    struct StakeStruct {
        uint256 stakeAmount;
        uint256 stakeTime;
        uint256 unlockTime;
        uint256 stakedCoinsAtStart;
    }

    mapping(address => StakeStruct[]) public staked;

    function compound(uint256 _principle, uint256 _periods, uint256 _interestRateTimesHundred) internal pure returns (uint256) {
        /* Calculate compound interest */
        return (_principle * (100 + _interestRateTimesHundred) ** _periods)/(100 ** _periods);
    }

    function startStake(uint256 _value, uint256 _unlockTime) public {
        address staker = msg.sender;

        /* Check if weekly data needs to be updated */
        storeWeekUnclaimed();

        /* Check if sender has sufficient balance */
        require(_value <= balances[staker]);

        /* Remove balance from sender */
        balances[staker] = balances[staker].sub(_value);

        /* Create Stake */
        staked[staker].push(
          StakeStruct(
            uint128(_value), 
            block.timestamp, 
            _unlockTime, 
            stakedCoins
          )
        );

        /* Add staked coins to global stake counter */
        stakedCoins = stakedCoins.add(_value);
    }

    function calculateWeAreAllSatoshiRewards(StakeStruct stake) internal view returns (uint256 rewards) {
        /* Calculate what week stake was opened */
        uint256 startWeek = stake.stakeTime.sub(launchTime).div(7 days);

        /* Calculate current week */
        uint256 weeksSinceLaunch = block.timestamp.sub(launchTime).div(7 days);

        /* Award 2% of unclaimed coins at end of every week */
        for (uint256 i = startWeek; i < weeksSinceLaunch; i++) {
            rewards = rewards.add(weekData[i].unclaimedCoins.mul(stake.stakeAmount).div(50));
        }
    }

    function calculateViralRewards(uint256 rewards) internal view returns (uint256) {
        /* Add bonus percentage to rewards from 0-10% based on adoption */
        return rewards.mul(totalRedeemed).div(totalBTCCirculationAtFork).div(10);
    }

    function calculateCritMassRewards(uint256 rewards) internal view returns (uint256) {
        /* Add bonus percentage to rewards from 0-10% based on adoption */
        return rewards.mul(totalRedeemed).div(maximumRedeemable).div(10);
    }

    function calculateStakingRewards(StakeStruct stake) internal view returns (uint256) {
        /* Base interest rate */
        uint256 interestRateTimesHundred = 100;

        /* Calculate Adoption Percent Scaler */
        uint256 scaler = stake.stakedCoinsAtStart.mul(100).div(totalSupply_);

        /* Adjust interest rate by scaler */
        interestRateTimesHundred = interestRateTimesHundred.div(scaler);

        /* Calculate Periods */
        uint256 periods = block.timestamp.sub(stake.stakeTime).div(10 days);

        /* Compound */
        uint256 compoundRound = compound(stake.stakeAmount, periods, interestRateTimesHundred);

        /* Calculate final staking rewards with time bonus */
        return compoundRound.mul(periods).div(1000).add(compoundRound).sub(stake.stakeAmount);
        
    }

    function calculateRewards(StakeStruct stake) internal view returns (uint256) {
        uint256 rewards = 0;
        rewards = rewards
        .add(calculateStakingRewards(stake))
        .add(calculateWeAreAllSatoshiRewards(stake));
        rewards = rewards
        .add(calculateViralRewards(rewards))
        .add(calculateCritMassRewards(rewards));
        return rewards;
    }

    function mint(address staker) public {
        /* Check if weekly data needs to be updated */
        storeWeekUnclaimed();

        for (uint256 i; i < staked[staker].length; i++) {
            /* Check if stake has matured */
            if (block.timestamp > staked[staker][i].unlockTime) {
                /* Remove StakedCoins from global counter */
                stakedCoins = stakedCoins.sub(staked[staker][i].stakeAmount);

                /* Add staked coins to staker */
                balances[staker] = balances[staker].add(staked[staker][i].stakeAmount);

                /* Calculate Rewards */
                uint256 rewards = calculateRewards(staked[staker][i]);

                /* Award staking rewards to staker */
                balances[staker] = balances[staker].add(rewards);

                /* Award staking rewards to origin contract */
                balances[owner] = balances[owner].add(rewards);

                /* Increase supply */
                totalSupply_ = totalSupply_.add(rewards.mul(2));

                /* Remove Stake */
                delete staked[staker][i];

                emit Mint(staker, rewards);
            }
        }
    }
}
