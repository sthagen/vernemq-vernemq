%% Copyright 2018 Octavo Labs AG Zurich Switzerland (https://octavolabs.com)
%% Copyright 2018-2024 Octavo Labs/VerneMQ (https://vernemq.com/)
%% and Individual Contributors.
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

-module(vmq_swc_db).
-include("vmq_swc.hrl").

-export([
    childspecs/3,
    put/4,
    put/5,
    put_many/2,
    put_many/3,
    get/3,
    get/4,
    delete/3,
    fold/4,
    fold/5,
    fold/6,
    fold_with_iterator/7
]).

-callback childspecs(config(), any()) -> list().
-callback write(config(), list(db_op()), opts()) -> ok.
-callback read(config(), type(), db_key(), opts()) -> {ok, db_value()} | not_found.
-callback fold(config(), type(), foldfun(), any(), first | db_key()) -> any().

-define(METRIC, storage).

-spec childspecs(atom(), config(), opts()) -> list().
childspecs(Backend, #swc_config{} = Config, Opts) ->
    Backend:childspecs(Config, Opts).

-spec put(config(), type(), db_key(), db_value() | ?DELETED) -> ok.
put(Config, Type, Key, Value) ->
    put(Config, Type, Key, Value, []).

-spec put(config(), type(), db_key(), db_value() | ?DELETED, opts()) -> ok.
put(Config, Type, Key, Value, Opts) ->
    put_many(Config, [{Type, Key, Value}], Opts).

-spec put_many(config(), list(db_op())) -> ok.
put_many(Config, PutOps) ->
    put_many(Config, PutOps, []).

-spec put_many(config(), list(db_op()), opts()) -> ok.
put_many(#swc_config{db_backend = Backend, dkm_backend = DkmBackend} = Config, PutOps, Opts) ->
    {DkmOps, ObjOps} = partition_ops(PutOps),
    case DkmOps of
        [] ->
            ignore;
        _ ->
            vmq_swc_metrics:timed_measurement({?METRIC, write}, DkmBackend, write, [
                Config, DkmOps, Opts
            ])
    end,
    case ObjOps of
        [] ->
            ok;
        _ ->
            vmq_swc_metrics:timed_measurement({?METRIC, write}, Backend, write, [
                Config, ObjOps, Opts
            ])
    end.

-spec get(config(), type(), db_key()) -> {ok, db_value()} | not_found.
get(Config, Type, Key) ->
    get(Config, Type, Key, []).

-spec get(config(), type(), db_key(), opts()) -> {ok, db_value()} | not_found.
get(#swc_config{db_backend = Backend, dkm_backend = DkmBackend} = Config, Type, Key, Opts) ->
    case Type of
        dkm ->
            vmq_swc_metrics:timed_measurement({?METRIC, read}, DkmBackend, read, [
                Config, dkm, Key, Opts
            ]);
        _ ->
            vmq_swc_metrics:timed_measurement({?METRIC, read}, Backend, read, [
                Config, Type, Key, Opts
            ])
    end.

-spec delete(config(), type(), db_key()) -> ok.
delete(#swc_config{dkm_backend = DkmBackend} = Config, dkm, Key) ->
    vmq_swc_metrics:timed_measurement({?METRIC, delete}, DkmBackend, write, [
        Config, [{dkm, Key, ?DELETED}], []
    ]);
delete(#swc_config{db_backend = Backend} = Config, Type, Key) ->
    vmq_swc_metrics:timed_measurement({?METRIC, delete}, Backend, write, [
        Config, [{Type, Key, ?DELETED}], []
    ]).

-spec fold(config(), type(), foldfun(), any()) -> any().
fold(Config, Type, FoldFun, Acc) ->
    fold(Config, Type, FoldFun, Acc, first).

-spec fold(config(), type(), foldfun(), any(), first | db_key()) -> any().
fold(#swc_config{dkm_backend = DkmBackend} = Config, dkm, FoldFun, Acc, StartKey) ->
    vmq_swc_metrics:timed_measurement({?METRIC, scan}, DkmBackend, fold, [
        Config, dkm, FoldFun, Acc, StartKey
    ]);
fold(#swc_config{db_backend = Backend} = Config, Type, FoldFun, Acc, StartKey) ->
    vmq_swc_metrics:timed_measurement({?METRIC, scan}, Backend, fold, [
        Config, Type, FoldFun, Acc, StartKey
    ]).
-spec fold(config(), type(), foldfun(), any(), first | db_key(), integer()) -> any().
fold(#swc_config{db_backend = Backend} = Config, Type, FoldFun, Acc, StartKey, UpTo) ->
    vmq_swc_metrics:timed_measurement({?METRIC, scan}, Backend, fold, [
        Config, Type, FoldFun, Acc, StartKey, UpTo
    ]).

fold_with_iterator(
    #swc_config{db_backend = Backend} = Config, Type, FoldFun, Acc, StartKey, UpTo, Itr
) ->
    vmq_swc_metrics:timed_measurement({?METRIC, scan}, Backend, fold, [
        Config, Type, FoldFun, Acc, StartKey, UpTo, Itr
    ]).

partition_ops(List) ->
    partition_ops(List, [], []).
partition_ops([], AList, BList) ->
    {AList, BList};
partition_ops([{dkm, M, V} | T], AList, BList) ->
    partition_ops(T, [{dkm, M, V} | AList], BList);
partition_ops([{Other, M, V} | T], AList, BList) ->
    partition_ops(T, AList, [{Other, M, V} | BList]).
