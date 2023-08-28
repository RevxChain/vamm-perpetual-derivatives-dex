// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library Math {
    uint internal constant INIT_LOCK_AMOUNT = 1;
    uint internal constant DENOMINATOR = 1000;
    uint internal constant PRECISION = 10000;
    uint internal constant ONE_YEAR = 52 weeks;
    uint internal constant REVERSE_PRECISION = 1e12;
    uint internal constant ACCURACY = 1e18;
    uint internal constant DOUBLE_ACC = 1e36;
    
    function stableToPrecision(uint amount) internal pure returns(uint) {
        return amount * REVERSE_PRECISION;
    }

    function precisionToStable(uint amount) internal pure returns(uint) {
        return amount / REVERSE_PRECISION;
    }

    function sqrt(uint y) internal pure returns(uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function mulDiv(uint a, uint b, uint denominator) internal pure returns(uint result) {
        unchecked {
            uint prod0 = a * b;
            uint prod1;
            assembly {
                let mm := mulmod(a, b, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            require(denominator > prod1);

            if (prod1 == 0) {
                assembly {
                    result := div(prod0, denominator)
                }
                return result;
            }
            assembly {
                let remainder := mulmod(a, b, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }
            uint twos = (0 - denominator) & denominator;
            assembly {
                denominator := div(denominator, twos)
            }
            assembly {
                prod0 := div(prod0, twos)
            }
            assembly {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;
            uint inv = (3 * denominator) ^ 2;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            inv *= 2 - denominator * inv;
            result = prod0 * inv;
        }
    }
}
