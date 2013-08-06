%%% File    : exometer_ebuf.erl
%%% Author  : Tony Rogvall <tony@rogvall.se>
%%% Description : Double event buffering
%%% Created : 29 Sep 2009 by Tony Rogvall <tony@rogvall.se>

-module(exometer_slide).

-export([new/1,
	 add_element/2,
	 add_element/3,
	 to_list/1,
	 fold/3]).

-compile(export_all).

-import(lists, [reverse/1, sublist/3]).
-import(exometer, [timestamp/0]).

%% Fixed size event buffer
-record(slide, {size = 0 :: integer(),  % ms window
		last = 0 :: integer(), % millisecond timestamp
		cur_size = 0 :: integer(),
		buf1 = []    :: list(),
		buf2 = []    :: list()}).

-spec new(integer()) -> #slide{}.
%%
new(Size) ->
    #slide{size = Size,
	   last = timestamp(),
	   buf1 = [],
	   buf2 = []}.

-spec add_element(any(), #slide{}) -> #slide{}.
%%
add_element(Evt, Slide) ->
    add_element(timestamp(), Evt, Slide).
add_element(_TS, _Evt, Slide) when Slide#slide.size == 0 ->
    Slide;
add_element(TS, Evt, #slide{last = Last, size = Sz,
			    buf1 = Buf1} = Slide) ->
    if TS - Last > Sz ->
	    %% swap
	    Slide#slide{last = TS,
			buf1 = [{TS, Evt}],
			buf2 = Buf1};
       true ->
	    Slide#slide{buf1 = [{TS, Evt} | Buf1]}
    end.

-spec to_list(#slide{}) -> list().
%%
to_list(#slide{size = Sz}) when Sz == 0 ->
    [];
to_list(#slide{size = Sz, buf1 = Buf1, buf2 = Buf2}) ->
    Start = timestamp() - Sz,
    take_since(Buf2, Start, reverse(Buf1)).

fold(_Fun, _Acc, #slide{size = Sz}) when Sz == 0 ->
    [];
fold(Fun, Acc, #slide{size = Sz, buf1 = Buf1, buf2 = Buf2}) ->
    Start = timestamp() - Sz,
    lists:foldr(
      Fun, lists:foldl(Fun, Acc, take_since(Buf2, Start, [])), Buf1).

take_since([{TS,_} = H|T], Start, Acc) when TS >= Start ->
    take_since(T, Start, [H|Acc]);
take_since(_, _, Acc) ->
    %% Don't reverse; already the wanted order.
    Acc.

test() ->
    S = new(1000),
    S1 = lists:foldl(
	   fun({K,V}, Acc) ->
		   Acc1 = add_element({K,V}, Acc),
		   Acc1
	   end, S, [{K, V} || K <- lists:seq(1,100),
			      V <- lists:seq(1,100)] ++
	       [{K,V} || K <- [3,4],
			 V <- [b,c]]),
    timer:tc(?MODULE, build_histogram, [S1]).

build_histogram(S) ->
    try
	fold(fun({_T, {K, _V}}, Acc) ->
		     pd_incr(K), Acc
	     end, ok, S),
	get()
    after
	erase()
    end.

pd_incr(K) ->
    case get(K) of
	undefined ->
	    put(K, 1);
	N ->
	    put(K, N+1)
    end.