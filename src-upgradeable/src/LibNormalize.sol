// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title LibNormalize
/// @notice 最低限の ASCII 正規化（NFKC / 小文字化 / trim / 連続空白縮約）
///         完全な Unicode NFKC はオフチェーンで実施する前提。
library LibNormalize {
    /* ───────────────────────── internal pure ───────────────────────── */

    /// @dev 文字列を正規化して bytes にして返す（UTF-8 そのまま）
    function normalize(string memory s) internal pure returns (bytes memory) {
        bytes memory b = bytes(s);
        bytes memory out;
        uint256 len;

        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];

            // 0x20 == space
            if (c == 0x20) {
                // 連続スペース・先頭スペースをスキップ
                if (len == 0 || out[len - 1] == 0x20) continue;
            }

            // ASCII Upper → Lower
            if (c >= 0x41 && c <= 0x5A) {
                c = bytes1(uint8(c) + 32);
            }

            out = abi.encodePacked(out, c);
            len++;
        }

        // 末尾スペース除去
        if (len > 0 && out[len - 1] == 0x20) {
            assembly {
                mstore(out, sub(len, 1))
            }
        }
        return out;
    }

    /// @dev 正規化した上で keccak256 ハッシュを返す
    function normHash(string memory s) internal pure returns (bytes32) {
        return keccak256(normalize(s));
    }
}
