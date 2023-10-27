// SPDX-License-Identifier: GPL-3.0

/**
 *     NOTICE
 *
 *     This software is licensed under a proprietary license or the GPL v.3.
 *     If you choose to receive it under the GPL v.3 license, the following applies:
 *
 *     Copyright (C) 2023, MonetaForge.
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma solidity 0.8.17;
// solhint-disable-next-line no-global-import
import "../IModularCompliance.sol";
// solhint-disable-next-line no-global-import
import "./AbstractModule.sol";
// solhint-disable-next-line no-global-import
import "../../../token/IToken.sol";
// solhint-disable-next-line no-global-import
import "@openzeppelin/contracts/access/Ownable.sol";
// solhint-disable-next-line no-global-import
import "./MFLockState.sol";

contract MFLockModule is AbstractModule, Ownable {

    MFLockState private _lockState;
    uint256 private _maxTimelockDays = 365; // default timelock days

    event LockStateAddress(address indexed admin, address oldAddress, address newAddress);

    constructor(address _lockStateAddress) {
        require(_lockStateAddress != address(0), "invalid argument - zero address");
        _lockState = MFLockState(_lockStateAddress);
    }

    /**
    *  @dev See {ICompliance-transferred}.
    */
    function moduleTransferAction(address _from, address _to, uint256 _value) external override onlyComplianceCall {

        uint256 _unlockedBalance =  getUnlockedBalance(msg.sender, _from, 0, _value); //determine unlocked balance before transfer
        if (_value > _unlockedBalance) { 
            (uint256 _fromTimestamp, uint256 _fromBalance) = _lockState.getTimeLock(msg.sender, _from);
            (uint256 _toTimestamp, uint256 _toBalance) =  _lockState.getTimeLock(msg.sender, _to);

            if (_fromTimestamp > _toTimestamp) {
		        _toTimestamp = _fromTimestamp;
	        } 

            if (_fromBalance > (_value - _unlockedBalance)) {
                _toBalance += (_value - _unlockedBalance);
                _fromBalance -= (_value - _unlockedBalance);
                _lockState.setTimeLock(msg.sender, _from, _fromTimestamp, _fromBalance);
	        } else {
                _toBalance += _fromBalance;
                _lockState.releaseTimeLock(msg.sender, _from);
	        } 	
            _lockState.setTimeLock(msg.sender, _to, _toTimestamp, _toBalance);
        }
    }

    /**
     *  @dev See {ICompliance-created}.
     */
    function moduleMintAction(address _to, uint256 _value) external override onlyComplianceCall {

        (uint256 _toTimestamp, uint256 _toBalance) =  _lockState.getTimeLock(msg.sender, _to);
        if (_toTimestamp > block.timestamp) {  //active timelock
            _toBalance += _value;
        } else {
            _toBalance = _value;
        }
        _lockState.setTimeLock(msg.sender, _to, block.timestamp + ( _maxTimelockDays * 1 days), _toBalance);
    }

    /**
     *  @dev See {ICompliance-destroyed}.
     */
    function moduleBurnAction(address _from, uint256 _value) external override onlyComplianceCall {

        if (_value > getUnlockedBalance(msg.sender, _from,0, _value)) { 
            (uint256 _fromTimestamp, uint256 _fromBalance) = _lockState.getTimeLock(msg.sender, _from);
            if (_fromBalance > _value) {
                _fromBalance -= _value;
                _lockState.setTimeLock(msg.sender, _from, _fromTimestamp, _fromBalance);
            } else {
                _lockState.releaseTimeLock(msg.sender, _from);
            }
        }
    }

    function setLockStateAddress(address _lockStateAddress) external onlyOwner {
        require(_lockStateAddress != address(0), "ADDRESS CAN NOT BE 0x0");
        address oldAddress = address(_lockState);
        _lockState = MFLockState(_lockStateAddress);
        emit LockStateAddress(msg.sender, oldAddress, address(_lockState));
    }

    function setMaxTimeLockDays(uint256 _maxDays) external onlyOwner {
        _maxTimelockDays = _maxDays;
    }

    function getMaxTimeLockDays() external view returns(uint256) {
        return _maxTimelockDays;
    }

    function getLockStateAddress() external view returns (MFLockState) {
        return _lockState;
    }

    /**
     *  @dev See {IModule-moduleCheck}.
     *  checks if the country of address _to is not restricted for this _compliance
     *  returns TRUE if the country of _to is not restricted for this _compliance
     *  returns FALSE if the country of _to is restricted for this _compliance
     */
    // solhint-disable-next-line code-complexity
    function moduleCheck(
        address _from,
        address _to,
        uint256 _value,
        address _compliance
    ) external view override returns (bool){

        // check for freeze timelock
        if ((_lockState.getFreezeTimeLock(msg.sender, _from) > block.timestamp)) {
            return false;
        }

        if (_from == address(0)) {   //always allow minting
            return true;
        }
        
        uint16 _toCountry = IToken(IModularCompliance(_compliance).getTokenBound()).identityRegistry().investorCountry(_to);
        uint16 _fromCountry = IToken(IModularCompliance(_compliance).getTokenBound()).identityRegistry().investorCountry(_from);

        if (_toCountry == 840 || _toCountry == 901) { //check if sending to US resident
            // Only Accredited US investors can send to accredited US investors before restricted period ends
            if (_fromCountry == 840 && _toCountry == 840) { 
                return true;                
            } 
            // Investors cannot send to any US investors before restricted period ends
            if (_value > getUnlockedBalance(_compliance, _from, 0, 0)) { //12 month lock
                return false;
            }
            return true;
        } 

        if (_toCountry == 124 || _toCountry == 902) { //check if sending to a CAD resident
            // Investors cannot send to any CAD investors before restricted period ends
            if (_value > getUnlockedBalance(_compliance, _from, 240, 0)) { //4 month lock
                return false;
            }
            // Only ATS or accredited to accredited investors is allowed after restricted period
            if (_fromCountry == 900 || (_fromCountry == 124 && _toCountry == 124)) {
                return true;
            }
            return false;           
        }
        return true;
    }
    
    /// @dev Check total balance locked at the current timestamp
    /// @param account The address to check
    /// @return balanceLocked The amount of tokens reserved until the timestamp.
    function getLockedBalance(address _compliance, address account, uint256 _daysOffset) public view returns(uint256 balanceLocked) {
        uint256 totalLocked = 0;
        (uint256 _timestamp, uint256 _minBalance) = _lockState.getTimeLock(_compliance, account);
        _daysOffset *= 1 days; // convert to timestamp
        if (_daysOffset > _timestamp) {
            _daysOffset = _timestamp;
        }
        if ((_timestamp - _daysOffset) > block.timestamp) {
            totalLocked = _minBalance;
        }
        return totalLocked;
    }

    // @dev Checks how many tokens are available to transfer
    /// @param account The address to check
    /// @return balanceUnlocked The number of tokens that can be accessed now
    function getUnlockedBalance(address _compliance, address account, uint256 _daysOffset, uint256 _valueOffset) public view 
            returns (uint256 balanceUnlocked) {
        uint256 lockedNow = getLockedBalance(_compliance, account, _daysOffset);
        uint256 _currentBalance = IToken(IModularCompliance(_compliance).getTokenBound()).balanceOf(account) + _valueOffset;
        if (lockedNow > _currentBalance) {
            lockedNow = _currentBalance;
        }
        return _currentBalance - lockedNow;
    }
}
