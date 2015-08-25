%
% The contents of this file are subject to the Mozilla Public License
% Version 1.1 (the "License"); you may not use this file except in
% compliance with the License. You may obtain a copy of the License at
% http://www.mozilla.org/MPL/
%
% Copyright (c) 2015 Petr Gotthard <petr.gotthard@centrum.cz>
%

% registry of server content handlers
% provides the .well-known/code resource and (in future) content queries
-module(coap_server_content).
-behaviour(gen_server).

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).
-export([add_handler/3, get_handler/1]).

-include("coap.hrl").

-record(state, {reg}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

add_handler(Process, Link, Public) ->
    gen_server:call(?MODULE, {add_handler, Process, Link, Public}).

get_handler(Message) ->
    UriPath = proplists:get_value(uri_path, Message#coap_message.options, []),
    gen_server:call(?MODULE, {get_handler, UriPath}).

init(_Args) ->
    {ok, #state{reg=
        % RFC 6690, Section 4
        % the .well-known/core itself is not listed under .well-known/core
        [{?MODULE, {absolute, [".well-known", "core"], []}, false}]
    }}.

handle_call({add_handler, Process, Link, Public}, _From, State=#state{reg=Reg}) ->
    {reply, ok, State#state{reg=[{Process, Link, Public} | Reg]}};

handle_call({get_handler, UriPath}, _From, State=#state{reg=Reg}) ->
    case lists:foldl(
        fun(Entry={_Process, {_, RegisteredUri, _}, _Public}, Acc) ->
            case {lists:sublist(UriPath, length(RegisteredUri)), Acc} of
                {RegisteredUri, undefined} -> Entry;
                {RegisteredUri, {BestUri, _}} ->
                    if
                        length(RegisteredUri) > length(BestUri) -> Entry;
                        true -> Acc
                    end;
                _AnythingElse -> Acc
            end
        end, undefined, Reg)
    of
        {Res, _, _} -> {reply, Res, State};
        undefined -> {reply, undefined, State}
    end.

handle_cast(Request, State) ->
    io:fwrite("coap_server_content unknown cast ~p~n", [Request]),
    {noreply, State}.

handle_info({coap_request, Channel, _Ref, Request=#coap_message{method='get'}}, State=#state{reg=Reg}) ->
    coap_request:reply_content(Channel, Request, <<"application/link-format">>, format_links(Reg)),
    {noreply, State};
handle_info({coap_request, Channel, _Ref, Request}, State) ->
    coap_request:reply(Channel, Request, {error, method_not_allowed}),
    {noreply, State};
handle_info(_Unknown, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

format_links(Reg) ->
    LinkList = lists:filtermap(
        fun({_, Link, true}) -> {true, Link};
            ({_, _, false}) -> false
        end, Reg),
    list_to_binary(core_link:encode(LinkList)).

% end of file