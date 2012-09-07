%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ Federation.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2012 VMware, Inc.  All rights reserved.
%%

-module(rabbit_federation_upstream).

-include("rabbit_federation.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-export([set_for/1, for/1, for/2, to_table/1, to_string/1]).
%% For testing
-export([from_set/2]).

-import(rabbit_misc, [pget/2, pget/3]).
-import(rabbit_federation_util, [name/1, vhost/1]).

%%----------------------------------------------------------------------------

set_for(X) -> rabbit_policy:get(<<"federation-upstream-set">>, X).

for(X) ->
    case set_for(X) of
        {ok, UpstreamSet}  -> from_set(UpstreamSet, X);
        {error, not_found} -> []
    end.

for(X, UpstreamName) ->
    case set_for(X) of
        {ok, UpstreamSet}  -> from_set(UpstreamSet, X, UpstreamName);
        {error, not_found} -> []
    end.

to_table(#upstream{original_uri = URI,
                   params       = Params,
                   exchange = X}) ->
    {table, [{<<"uri">>,          longstr, URI},
             {<<"virtual_host">>, longstr, vhost(Params)},
             {<<"exchange">>,     longstr, name(X)}]}.

to_string(#upstream{original_uri = URI,
                    exchange     = #exchange{name = XName}}) ->
    print("~s on ~s", [rabbit_misc:rs(XName), URI]).

print(Fmt, Args) -> iolist_to_binary(io_lib:format(Fmt, Args)).

from_set(SetName, X, UpstName) ->
    rabbit_federation_util:find_upstreams(UpstName, from_set(SetName, X)).

from_set(<<"all">>, X) ->
    Connections = rabbit_runtime_parameters:list(
                    vhost(X), <<"federation-upstream">>),
    Set = [[{<<"upstream">>, pget(key, C)}] || C <- Connections],
    from_set_contents(Set, X);

from_set(SetName, X) ->
    case rabbit_runtime_parameters:value(
           vhost(X), <<"federation-upstream-set">>, SetName) of
        not_found -> [];
        Set       -> from_set_contents(Set, X)
    end.

from_set_contents(Set, X) ->
    Results = [from_set_element(P, X) || P <- Set],
    [R || R <- Results, R =/= not_found].

from_set_element(UpstreamSetElem, X) ->
    Name = bget(upstream, UpstreamSetElem, []),
    case rabbit_runtime_parameters:value(
           vhost(X), <<"federation-upstream">>, Name) of
        not_found  -> not_found;
        Upstream   -> from_props_connection(UpstreamSetElem, Name, Upstream, X)
    end.

from_props_connection(U, Name, C, X) ->
    URI = bget(uri, U, C),
    {ok, Params} = amqp_uri:parse(binary_to_list(URI), vhost(X)),
    XNameBin = bget(exchange, U, C, name(X)),
    #upstream{params          = Params,
              original_uri    = URI,
              exchange        = with_name(XNameBin, vhost(Params), X),
              prefetch_count  = bget('prefetch-count',  U, C, ?DEFAULT_PREFETCH),
              reconnect_delay = bget('reconnect-delay', U, C, 1),
              max_hops        = bget('max-hops',        U, C, 1),
              expires         = bget(expires,           U, C, none),
              message_ttl     = bget('message-ttl',     U, C, none),
              trust_user_id   = bget('trust-user-id',   U, C, false),
              ha_policy       = bget('ha-policy',       U, C, none),
              name            = Name}.

%%----------------------------------------------------------------------------

bget(K, L1, L2) -> bget(K, L1, L2, undefined).

bget(K0, L1, L2, D) ->
    K = a2b(K0),
    case pget(K, L1, undefined) of
        undefined -> pget(K, L2, D);
        Result    -> Result
    end.

a2b(A) -> list_to_binary(atom_to_list(A)).

with_name(XNameBin, VHostBin, X) ->
    X#exchange{name = rabbit_misc:r(VHostBin, exchange, XNameBin)}.
