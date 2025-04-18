module swap::router {
    use swap::math;
    use swap::swap_utils;
    use swap::swap_utils::PairAsset;
    use swap::swap_pool;

    const ERROR_SUFFICIENT_X_AMOUNT: u64 = 1;
    const ERROR_SUFFICIENT_Y_AMOUNT: u64 = 2;
    const ERROR_PAIR_NOT_CREATED: u64 = 3;

    public entry fun create_pair(
        creator: &signer,
        addr_x: address,
        addr_y: address
    ) {
        swap_pool::create_pair(
            creator,
            addr_x,
            addr_y
        );
    }

    fun is_pair_created_internal(
        addr_x: address,
        addr_y: address
    ) {
        assert!(swap_pool::exists_pair_asset(addr_x, addr_y), ERROR_PAIR_NOT_CREATED);
    }

    fun make_pair_asset(addr_x: address, addr_y: address): PairAsset {
        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        let pair_asset: PairAsset = if (is_x_to_y) {
            swap_utils::make_pair_asset(addr_x, addr_y)
        } else {
            swap_utils::make_pair_asset(addr_y, addr_x)
        };
        pair_asset
    }

    public entry fun add_liquidity(
        sender: &signer,
        addr_x: address,
        addr_y: address,
        amount_x_desired: u64,
        amount_y_desired: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ) {
        is_pair_created_internal(addr_x, addr_y);
        swap_pool::create_pair(
            sender,
            addr_x,
            addr_y
        );

        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        let pair_asset: PairAsset = make_pair_asset(addr_x, addr_y);

        let (amount_x, amount_y): (u64, u64);
        if (is_x_to_y) {
            (amount_x, amount_y, _) = swap_pool::add_liquidity(sender, pair_asset, amount_x_desired, amount_y_desired);
        } else {
            (amount_y, amount_x, _) = swap_pool::add_liquidity(sender, pair_asset, amount_y_desired, amount_x_desired);
        };

        assert!(amount_x >= amount_x_min, ERROR_SUFFICIENT_X_AMOUNT);
        assert!(amount_y >= amount_y_min, ERROR_SUFFICIENT_Y_AMOUNT);
    }

    public entry fun remove_liquidity(
        sender: &signer,
        addr_x: address,
        addr_y: address,
        liquidity: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ) {
        is_pair_created_internal(addr_x, addr_y);
        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        let pair_asset: PairAsset = make_pair_asset(addr_x, addr_y);

        let (amount_x, amount_y): (u64, u64);
        if (is_x_to_y) {
            (amount_x, amount_y) = swap_pool::remove_liquidity(sender, pair_asset, liquidity);
        } else {

            (amount_y, amount_x) = swap_pool::remove_liquidity(sender, pair_asset, liquidity);
        };

        assert!(amount_x >= amount_x_min, ERROR_SUFFICIENT_X_AMOUNT);
        assert!(amount_y >= amount_y_min, ERROR_SUFFICIENT_Y_AMOUNT);
    }

    fun get_intermediate_output_exact_x_to_y(
        is_x_to_y: bool,
        pair_asset: PairAsset,
        // addr_x: address,
        // addr_y: address,
        amount_x_in: u64
    ): u64 {
        if (is_x_to_y) {
            let y_out: u64 = swap_pool::swap_exact_x_to_y_direct(pair_asset, amount_x_in);
            y_out
        } else {
            let y_out: u64 = swap_pool::swap_exact_y_to_x_direct(pair_asset, amount_x_in);
            y_out
        }
    }

    public fun swap_exact_x_to_y_direct_external(
        addr_x: address,
        addr_y: address,
        amount_x_in: u64
    ): u64 {
        is_pair_created_internal(addr_x, addr_y);
        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        let pair_asset: PairAsset = make_pair_asset(addr_x, addr_y);
        let y_out: u64 = get_intermediate_output_exact_x_to_y(is_x_to_y, pair_asset, amount_x_in);
        y_out
    }

    fun get_amount_in_internal(
        is_x_to_y: bool,
        addr_x: address,
        addr_y: address,
        amount_y_out: u64
    ): u64 {
        is_pair_created_internal(addr_x, addr_y);
        let pair_asset: PairAsset = make_pair_asset(addr_x, addr_y);
        if (is_x_to_y) {
            let (reserve_in, reserve_out, _): (u64, u64, u64) = swap_pool::get_token_pair_reserve(pair_asset);
            math::get_amount_in(amount_y_out, reserve_in, reserve_out)
        } else {
            let (reserve_out, reserve_in, _): (u64, u64, u64) = swap_pool::get_token_pair_reserve(pair_asset);
            math::get_amount_in(amount_y_out, reserve_in, reserve_out)
        }
    }

    public fun get_amount_in(
        addr_x: address,
        addr_y: address,
        amount_y_out: u64
    ): u64 {
        is_pair_created_internal(addr_x, addr_y);
        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        get_amount_in_internal(
            is_x_to_y,
            addr_x,
            addr_y,
            amount_y_out
        )
    }

    fun get_intermediate_output_x_to_exact_y(
        is_x_to_y: bool,
        pair_asset: PairAsset,
        amount_x_in: u64
    ): u64 {
        if (is_x_to_y) {
            let y_out: u64 = swap_pool::swap_x_to_exact_y_direct(pair_asset, amount_x_in);
            y_out
        } else {
            let y_out: u64 = swap_pool::swap_y_to_exact_x_direct(pair_asset, amount_x_in);
            y_out
        }
    }

    public fun swap_x_to_exact_y_direct_external(
        addr_x: address,
        addr_y: address,
        amount_x_in: u64
    ): u64 {
        is_pair_created_internal(addr_x, addr_y);
        let is_x_to_y: bool = swap_utils::compare_symbol_fa(addr_x, addr_y);
        let pair_asset: PairAsset = make_pair_asset(addr_x, addr_y);
        let y_out: u64 = get_intermediate_output_x_to_exact_y(is_x_to_y, pair_asset, amount_x_in);
        y_out
    }




}