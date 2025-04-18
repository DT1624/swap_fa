module swap::math {

    const PERCENT_WITHOUT_FEE: u128 = 9975;
    const PERCENT_TOTAL: u128 = 10000;

    const EINSUFFICIENT_INPUT_AMOUNT: u64 = 1;
    const EINSUFFICIENT_LIQUIDITY: u64 = 2;

    /* public functions can be called in swap file*/
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
    ): u64 {
        assert!(reserve_in > 0 && reserve_out > 0, EINSUFFICIENT_LIQUIDITY);
        assert!(amount_out > 0 && amount_out < reserve_out, EINSUFFICIENT_INPUT_AMOUNT);

        let amount_out_without_fee: u128 = (amount_out as u128) * PERCENT_TOTAL;
        let numerator: u128 = amount_out_without_fee * (reserve_in as u128);
        let denominator: u128 = (reserve_out as u128) * PERCENT_WITHOUT_FEE - amount_out_without_fee;
        numerator += denominator - 1;
        ((numerator / denominator) as u64)
    }

    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
    ): u64 {
        assert!(reserve_in > 0 && reserve_out > 0, EINSUFFICIENT_LIQUIDITY);
        assert!(amount_in > 0, EINSUFFICIENT_INPUT_AMOUNT);
        let amount_in_without_fee: u128 = (amount_in as u128) * PERCENT_WITHOUT_FEE;
        let numerator: u128 = amount_in_without_fee * (reserve_out as u128);
        let denominator: u128 = (reserve_in as u128) * PERCENT_TOTAL + amount_in_without_fee;
        ((numerator / denominator) as u64)
    }

    public fun quote_y(
        amount_x: u64,
        reserve_x: u64,
        reserve_y: u64,
    ): u64 {
        assert!(reserve_x > 0 && reserve_y > 0, EINSUFFICIENT_LIQUIDITY);
        assert!(amount_x > 0, EINSUFFICIENT_INPUT_AMOUNT);
        let numerator: u128 = (amount_x as u128) * (reserve_y as u128);
        let denominator: u128 = (reserve_x as u128);
        ((numerator / denominator) as u64)
    }

    public fun quote_x(
        amount_y: u64,
        reserve_x: u64,
        reserve_y: u64,
    ): u64 {
        assert!(reserve_x > 0 && reserve_y > 0, EINSUFFICIENT_LIQUIDITY);
        assert!(amount_y > 0, EINSUFFICIENT_INPUT_AMOUNT);
        let numerator: u128 = (amount_y as u128) * (reserve_x as u128);
        let denominator: u128 = (reserve_y as u128);
        ((numerator / denominator) as u64)
    }
}