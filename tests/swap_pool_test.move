#[test_only]
module swap::swap_pool_test {
    use std::option;
    use std::signer;
    use aptos_std::debug::print;
    use swap::swap_utils;
    use swap::swap_utils::{PairAsset};
    use swap::swap_pool;
    use aptos_framework::timestamp;

    const ERROR_POOL_ADDRESS: u64 = 1;
    const ERROR_CREATE_PAIR: u64 = 2;

    #[test(creator = @swap)]
    fun test_init_module(creator: &signer) {
        swap_pool::init_for_test_pool(creator);
        assert!(swap_pool::exists_swap_info(), ERROR_POOL_ADDRESS);
        assert!(swap_pool::exists_global_pool(), ERROR_POOL_ADDRESS);
    }

    #[test(creator = @swap, user = @user)]
    #[expected_failure(abort_code = swap_pool::ERROR_SAME_FUNGIBLE_ASSET, location = swap_pool)]
    fun test_create_pair_same_fa(creator: &signer, user: &signer) {
        swap_pool::init_for_test_pool(creator);
        swap_utils::init_for_test_untils(creator);
        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        let addr_bnb: address = swap_utils::get_addr_fa(b"BNB");
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_bnb
        );
    }

    #[test(creator = @swap, user = @user, user1 = @0x123)]
    #[expected_failure(abort_code = swap_pool::ERROR_PAIR_ASSET_ALREADY_EXISTS, location = swap_pool)]
    fun test_create_exists_pair(creator: &signer, user: &signer, user1: &signer) {
        swap_pool::init_for_test_pool(creator);
        swap_utils::init_for_test_untils(creator);
        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"BNB",
            8,
            b"",
            b""
        );
        swap_utils::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        let addr_usd: address = swap_utils::get_addr_fa(b"USD");
        let addr_bnb: address = swap_utils::get_addr_fa(b"BNB");
        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );
        swap_pool::create_pair(
            user1,
            addr_usd,
            addr_bnb
        );
    }

    #[test(creator = @swap, user = @user, user1 = @0xcafe, aptos = @0x1)]
    fun test_add_liquidity(creator: &signer, user: &signer, user1: &signer, aptos: &signer) {
        timestamp::set_time_has_started_for_testing(aptos);
        swap_utils::init_for_test_untils(creator);
        swap_pool::init_for_test_pool(creator);
        swap_utils::init_FA(
            user,
            option::none(),
            b"USDT",
            b"USD",
            8,
            b"",
            b""
        );

        swap_utils::init_FA(
            user,
            option::none(),
            b"Binance",
            b"TNB",
            8,
            b"",
            b""
        );
        let addr_usd: address = swap_utils::get_addr_fa(b"USD");
        let addr_bnb: address = swap_utils::get_addr_fa(b"TNB");

        let addr_user: address = signer::address_of(user);
        let addr_user1: address = signer::address_of(user1);

        swap_pool::create_pair(
            user,
            addr_bnb,
            addr_usd
        );

        let pa: PairAsset = swap_utils::make_pair_asset(addr_bnb, addr_usd);
        assert!(swap_pool::exists_pa(pa), ERROR_CREATE_PAIR);

        let addr_pa: address = swap_utils::get_addr_pair_asset(pa);

        // mint to user
        swap_utils::mint_fa(user, addr_bnb, addr_user, 100);
        swap_utils::mint_fa(user, addr_usd, addr_user, 200);
        assert!(swap_pool::get_balance(addr_bnb, addr_user) == 100, 1);
        assert!(swap_pool::get_balance(addr_usd, addr_user) == 200, 2);

        // mint to user 1
        swap_utils::mint_fa(user, addr_bnb, addr_user1, 100);
        swap_utils::mint_fa(user, addr_usd, addr_user1, 80);
        assert!(swap_pool::get_balance(addr_bnb, addr_user1) == 100, 3);
        assert!(swap_pool::get_balance(addr_usd, addr_user1) == 80, 4);
        // check total supply each FA
        assert!(swap_pool::get_total_supply(addr_bnb) == 200, 5);
        assert!(swap_pool::get_total_supply(addr_usd) == 280, 6);
        // check amount pa in each user's store
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 0, 7);
        assert!(swap_pool::get_balance(addr_pa, addr_user1) == 0, 8);
        // check total supply pa
        assert!(swap_pool::get_total_supply(addr_pa) == 0, 9);
        assert!(swap_pool::get_total_supply(addr_bnb) == 200, 9);
        assert!(swap_pool::get_total_supply(addr_usd) == 280, 9);

        // user add liquidity
        swap_pool::test_add_liquidity(user, pa, 50, 50);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 50, 9);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 50, 10);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 40, 11);
        assert!(swap_pool::get_total_supply(addr_pa) == 50, 12);

        // user1 add liquidity
        swap_pool::test_add_liquidity(user1, pa, 20, 60);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 70, 13);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 70, 14);
        assert!(swap_pool::get_balance(addr_pa, addr_user1) == 20, 15);
        assert!(swap_pool::get_total_supply(addr_pa) == 70, 16);

        // user remove liquidity
        swap_pool::test_remove_liquidity(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 60, 17);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 60, 18);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 30, 19);
        assert!(swap_pool::get_total_supply(addr_pa) == 60, 20);

        // user swap amount exact x to y
        swap_pool::test_swap_exact_x_to_y(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 70, 21);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 52, 22);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 30, 23);
        assert!(swap_pool::get_total_supply(addr_pa) == 60, 24);

        swap_pool::test_swap_x_to_exact_y(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 87, 25);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 42, 26);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 30, 27);
        assert!(swap_pool::get_total_supply(addr_pa) == 60, 28);

        swap_pool::test_swap_exact_y_to_x(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 71, 29);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 52, 30);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 30, 31);
        assert!(swap_pool::get_total_supply(addr_pa) == 60, 32);

        swap_pool::test_swap_y_to_exact_x(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 61, 33);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 61, 34);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 30, 35);
        assert!(swap_pool::get_total_supply(addr_pa) == 60, 36);
        // user swap amount x to exact y
        swap_pool::test_remove_liquidity(user, pa, 10);
        assert!(swap_pool::get_balance(addr_bnb, addr_pa) == 51, 17);
        assert!(swap_pool::get_balance(addr_usd, addr_pa) == 51, 18);
        assert!(swap_pool::get_balance(addr_pa, addr_user) == 20, 19);
        assert!(swap_pool::get_total_supply(addr_pa) == 50, 20);

        // let (a, b) = swap_utils::get_addr_fa_x_y(pa);
        // print(&swap_utils::compare_symbol_fa(a, b));
    }
}
