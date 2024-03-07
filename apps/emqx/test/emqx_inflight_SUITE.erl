%%--------------------------------------------------------------------
%% Copyright (c) 2017-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_inflight_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("eunit/include/eunit.hrl").

all() -> emqx_common_test_helpers:all(?MODULE).

t_contain(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new()),
    ?assert(emqx_inflight:contain(k, Inflight)),
    ?assertNot(emqx_inflight:contain(badkey, Inflight)).

t_lookup(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new()),
    ?assertEqual({value, v}, emqx_inflight:lookup(k, Inflight)),
    ?assertEqual(none, emqx_inflight:lookup(badkey, Inflight)).

t_insert(_) ->
    Inflight = emqx_inflight:insert(
        b,
        2,
        emqx_inflight:insert(
            a, 1, emqx_inflight:new()
        )
    ),
    ?assertEqual(2, emqx_inflight:size(Inflight)),
    ?assertEqual({value, 1}, emqx_inflight:lookup(a, Inflight)),
    ?assertEqual({value, 2}, emqx_inflight:lookup(b, Inflight)),
    ?assertError({key_exists, a}, emqx_inflight:insert(a, 1, Inflight)).

t_update(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new()),
    ?assertEqual(Inflight, emqx_inflight:update(k, v, Inflight)),
    ?assertError(function_clause, emqx_inflight:update(badkey, v, Inflight)).

t_resize(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new(2)),
    ?assertEqual(1, emqx_inflight:size(Inflight)),
    ?assertEqual(2, emqx_inflight:max_size(Inflight)),
    Inflight1 = emqx_inflight:resize(4, Inflight),
    ?assertEqual(4, emqx_inflight:max_size(Inflight1)),
    ?assertEqual(1, emqx_inflight:size(Inflight)).

t_delete(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new(2)),
    Inflight1 = emqx_inflight:delete(k, Inflight),
    ?assert(emqx_inflight:is_empty(Inflight1)),
    ?assertNot(emqx_inflight:contain(k, Inflight1)).

t_values(_) ->
    Inflight = emqx_inflight:insert(
        b,
        2,
        emqx_inflight:insert(
            a, 1, emqx_inflight:new()
        )
    ),
    ?assertEqual([1, 2], emqx_inflight:values(Inflight)),
    ?assertEqual([{a, 1}, {b, 2}], emqx_inflight:to_list(Inflight)).

t_fold(_) ->
    Inflight = maps:fold(
        fun emqx_inflight:insert/3,
        emqx_inflight:new(),
        #{a => 1, b => 2, c => 42}
    ),
    ?assertEqual(
        emqx_inflight:fold(fun(_, V, S) -> S + V end, 0, Inflight),
        lists:foldl(fun({_, V}, S) -> S + V end, 0, emqx_inflight:to_list(Inflight))
    ).

t_is_full(_) ->
    Inflight = emqx_inflight:insert(k, v, emqx_inflight:new()),
    ?assertNot(emqx_inflight:is_full(Inflight)),
    Inflight1 = emqx_inflight:insert(
        b,
        2,
        emqx_inflight:insert(
            a, 1, emqx_inflight:new(2)
        )
    ),
    ?assert(emqx_inflight:is_full(Inflight1)).

t_is_empty(_) ->
    Inflight = emqx_inflight:insert(a, 1, emqx_inflight:new(2)),
    ?assertNot(emqx_inflight:is_empty(Inflight)),
    Inflight1 = emqx_inflight:delete(a, Inflight),
    ?assert(emqx_inflight:is_empty(Inflight1)).

t_window(_) ->
    ?assertEqual([], emqx_inflight:window(emqx_inflight:new(0))),
    Inflight = emqx_inflight:insert(
        b,
        2,
        emqx_inflight:insert(
            a, 1, emqx_inflight:new(2)
        )
    ),
    ?assertEqual([a, b], emqx_inflight:window(Inflight)).

t_to_list(_) ->
    Inflight = lists:foldl(
        fun(Seq, InflightAcc) ->
            emqx_inflight:insert(Seq, integer_to_binary(Seq), InflightAcc)
        end,
        emqx_inflight:new(100),
        [1, 6, 2, 3, 10, 7, 9, 8, 4, 5]
    ),
    ExpList = [{Seq, integer_to_binary(Seq)} || Seq <- lists:seq(1, 10)],
    ?assertEqual(ExpList, emqx_inflight:to_list(Inflight)).

t_query(_) ->
    EmptyInflight = emqx_inflight:new(500),
    ?assertMatch(
        {[], #{continuation := end_of_data}}, emqx_inflight:query(EmptyInflight, #{limit => 50})
    ),
    ?assertMatch(
        {[], #{continuation := end_of_data}},
        emqx_inflight:query(EmptyInflight, #{continuation => <<"empty">>, limit => 50})
    ),
    ?assertMatch(
        {[], #{continuation := end_of_data}},
        emqx_inflight:query(EmptyInflight, #{continuation => none, limit => 50})
    ),

    Inflight = lists:foldl(
        fun(Seq, QAcc) ->
            emqx_inflight:insert(Seq, integer_to_binary(Seq), QAcc)
        end,
        EmptyInflight,
        lists:reverse(lists:seq(1, 114))
    ),

    LastCont = lists:foldl(
        fun(PageSeq, Cont) ->
            Limit = 10,
            PagerParams = #{continuation => Cont, limit => Limit},
            {Page, #{continuation := NextCont} = Meta} = emqx_inflight:query(Inflight, PagerParams),
            ?assertEqual(10, length(Page)),
            ExpFirst = PageSeq * Limit - Limit + 1,
            ExpLast = PageSeq * Limit,
            ?assertEqual({ExpFirst, integer_to_binary(ExpFirst)}, lists:nth(1, Page)),
            ?assertEqual({ExpLast, integer_to_binary(ExpLast)}, lists:nth(10, Page)),
            ?assertMatch(
                #{count := 114, continuation := IntCont} when is_integer(IntCont),
                Meta
            ),
            NextCont
        end,
        none,
        lists:seq(1, 11)
    ),
    {LastPartialPage, LastMeta} = emqx_inflight:query(Inflight, #{
        continuation => LastCont, limit => 10
    }),
    ?assertEqual(4, length(LastPartialPage)),
    ?assertEqual({111, <<"111">>}, lists:nth(1, LastPartialPage)),
    ?assertEqual({114, <<"114">>}, lists:nth(4, LastPartialPage)),
    ?assertMatch(#{continuation := end_of_data, count := 114}, LastMeta),

    ?assertMatch(
        {[], #{continuation := end_of_data}},
        emqx_inflight:query(Inflight, #{continuation => <<"not-existing-cont-id">>, limit => 10})
    ),

    {LargePage, LargeMeta} = emqx_inflight:query(Inflight, #{limit => 1000}),
    ?assertEqual(114, length(LargePage)),
    ?assertEqual({1, <<"1">>}, hd(LargePage)),
    ?assertEqual({114, <<"114">>}, lists:last(LargePage)),
    ?assertMatch(#{continuation := end_of_data}, LargeMeta),

    {FullPage, FullMeta} = emqx_inflight:query(Inflight, #{limit => 114}),
    ?assertEqual(114, length(FullPage)),
    ?assertEqual({1, <<"1">>}, hd(FullPage)),
    ?assertEqual({114, <<"114">>}, lists:last(FullPage)),
    ?assertMatch(#{continuation := end_of_data}, FullMeta),

    {EmptyPage, EmptyMeta} = emqx_inflight:query(Inflight, #{limit => 0}),
    ?assertEqual([], EmptyPage),
    ?assertMatch(#{continuation := none, count := 114}, EmptyMeta).
