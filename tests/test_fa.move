#[test_only]
module swap::test_fa {
    use std::option;
    use swap::swap_pool;
    use swap::swap_utils;
    use aptos_framework::coin;

    #[test_only(creator = @swap, user1 = @0x123, user2 = @0x234, user3 = @0x345)]
    public fun test_fa(creator: &signer, user1: &signer, user2: &signer, user3: &signer) {
        swap_utils::init_for_test_untils(creator);
        swap_pool::init_for_test_pool(creator);
        swap_utils::init_FA(
            user1,
            option::none(),
            b"Tether",
            b"USDT",
            6,
            b"",
            b""
        );

        swap_utils::init_FA(
            user1,
            option::none(),
            b"USD Coin",
            b"USDC",
            6,
            b"",
            b""
        );

        swap_utils::init_FA(
            user2,
            option::none(),
            b"Binance USD",
            b"BUSD",
            18,
            b"",
            b""
        );

        swap_utils::init_FA(
            user2,
            option::none(),
            b"TrueUSD",
            b"TUSD",
            6,
            b"",
            b""
        );

        swap_utils::init_FA(
            user2,
            option::none(),
            b"Bitcoin",
            b"BTC",
            8,
            b"",
            b""
        );

        swap_utils::init_FA(
            user2,
            option::none(),
            b"Ethereum",
            b"ETH",
            18,
            b"",
            b""
        );

        swap_utils::init_FA(
            user2,
            option::none(),
            b"Litecoin",
            b"LTC",
            8,
            b"",
            b""
        );

        swap_utils::init_FA(
            user3,
            option::none(),
            b"Ripple",
            b"XRP",
            6,
            b"",
            b""
        );

        swap_utils::init_FA(
            user3,
            option::none(),
            b"Dogecoin",
            b"DOGE",
            8,
            b"",
            b""
        );

    }
}
