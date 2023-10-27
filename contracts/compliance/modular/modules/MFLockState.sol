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
import "../../../roles/AgentRole.sol";

contract MFLockState is AgentRole {

    struct LockUp {
        uint256 timestamp; // unix timestamp to lock funds 
        uint256 minBalance; // minimal balance that has to remain until the timestamp
    }

    mapping(address => mapping(address => LockUp)) private _timeLock;
    mapping(address => mapping(address => uint256)) private _freezeTimeLock;

    event FreezeTimeLock(address indexed admin, address indexed account, uint256 value);

    modifier onlyAdmin() {
        require(owner() == msg.sender || isAgent(msg.sender),"MFLockState error : this address is not an owner or agent/module");
        _;
    }

    // Unix timestamp is the number of seconds since the Unix epoch of 00:00:00 UTC on 1 January 1970.
    function setFreezeTimeLock(address _compliance, address _account, uint256 _timestamp) external onlyAdmin {
        require(_account != address(0), "ADDRESS CAN NOT BE 0x0");
        require(_compliance != address(0), "ADDRESS CAN NOT BE 0x0");
        _freezeTimeLock[_compliance][_account] = _timestamp;
        emit FreezeTimeLock(msg.sender, _account, _timestamp);
    }

    function removeFreezeTimeLock(address _compliance, address _account) external onlyAdmin {
        require(_account != address(0), "ADDRESS CAN NOT BE 0x0");
        require(_compliance != address(0), "ADDRESS CAN NOT BE 0x0");
        _freezeTimeLock[_compliance][_account] = 0;
        emit FreezeTimeLock(msg.sender, _account, 0);
    }

    function setTimeLock(address _compliance, address _account, uint256 _timestamp, uint256 _minBalance) external onlyAdmin {
        require(_account != address(0), "ADDRESS CAN NOT BE 0x0");
        require(_compliance != address(0), "ADDRESS CAN NOT BE 0x0");
        require(_timestamp > block.timestamp, "LOCK TIMESTAMP CANNOT BE IN THE PAST");
        require(_minBalance > 0, "LOCKED BALANCE CANNOT BE ZERO");     
        _timeLock[_compliance][_account] = LockUp(_timestamp, _minBalance); 
    }

    function releaseTimeLock( address _compliance, address _account ) external onlyAdmin {
        require(_account != address(0), "ADDRESS CAN NOT BE 0x0");
        require(_compliance != address(0), "ADDRESS CAN NOT BE 0x0");
        // delete the lock entry
        delete _timeLock[_compliance][_account];           
    }

    function getFreezeTimeLock(address _compliance, address _account) external view returns(uint256 timestamp) {
        return _freezeTimeLock[_compliance][_account];
    }

    function getTimeLock(address _compliance,address _account) external view returns(uint256 lockedUntil, uint256 balanceLocked) {
        return (_timeLock[_compliance][_account].timestamp, _timeLock[_compliance][_account].minBalance);
    }
}