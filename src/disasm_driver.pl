%%===- Dl_operator.cpp -----------------------------------------*- perl -*-===%%
%%
%%  Copyright (C) 2019 GrammaTech, Inc.
%%
%%  This code is licensed under the GNU Affero General Public License
%%  as published by the Free Software Foundation, either version 3 of
%%  the License, or (at your option) any later version. See the
%%  LICENSE.txt file in the project root for license terms or visit
%%  https://www.gnu.org/licenses/agpl.txt.
%%
%%  This program is distributed in the hope that it will be useful,
%%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
%%  GNU Affero General Public License for more details.
%%
%%  This project is sponsored by the Office of Naval Research, One Liberty
%%  Center, 875 N. Randolph Street, Arlington, VA 22203 under contract #
%%  N68335-17-C-0700.  The content of the information does not necessarily
%%  reflect the position or policy of the Government and no official
%%  endorsement should be inferred.
%%
%%===----------------------------------------------------------------------===%%
:-module(disasm_driver,[disasm_binary/1]).


% command line options that are accepted
valid_option('-debug').
valid_option('-asm').
valid_option('-stir').
valid_option('-interpreted').
valid_option('-keep_start').
valid_option('-hints').
valid_option('-function_hints').


%sections decoded as code
code_section('.text').
code_section('.plt').
code_section('.init').
code_section('.fini').
code_section('.plt.got').

% name and alignment of sections decoded as data
data_section_descriptor('.got',8).

data_section_descriptor('.got.plt',8).
data_section_descriptor('.data.rel.ro',8).
data_section_descriptor('.init_array',8).
data_section_descriptor('.fini_array',8).
data_section_descriptor('.rodata',16).
data_section_descriptor('.data',16).



% when the parameter -asm is given we do not print some of the functions and sections
% that are added by the compiler/assembler
asm_skip_function('_start'):-
    \+option('-keep_start').
asm_skip_function('deregister_tm_clones').
asm_skip_function('register_tm_clones').
asm_skip_function('__do_global_dtors_aux').
asm_skip_function('frame_dummy').
asm_skip_function('__libc_csu_fini').
asm_skip_function('__libc_csu_init').
asm_skip_function('_dl_relocate_static_pie').
%asm_skip_function('__clang_call_terminate').

asm_skip_section('.comment').
asm_skip_section('.plt').
asm_skip_section('.init').
asm_skip_section('.fini').
asm_skip_section('.got').
asm_skip_section('.plt.got').
asm_skip_section('.got.plt').
asm_skip_symbol('_IO_stdin_used').

% we treat these sections in an special way
meta_section('.init_array').
meta_section('.fini_array').


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Top-level predicate

disasm_binary([File|Args]):-
    maplist(save_option,Args),
    set_prolog_flag(print_write_options,[quoted(false)]),

    (option('-asm')->format('/*~n',[]);true),
    
    format('Decoding binary~n',[]),
    file_directory_name(File, Dir),
    atom_concat(Dir,'/dl_files',Dir2),
    (\+exists_directory(Dir2)->
	 make_directory(Dir2);true),

    % call the datalog_decoder with the code sections and data sections defined above
    decode_sections(File,Dir2),
    format('Calling souffle~n',[]),
    
    % call souffle 
    (option('-interpreted')->
	 call_souffle(Dir2)
     ;
     call_compiled_souffle(File,Dir2)
    ),
    % read all the information inferred in datalog and
    % incorporate it to the prolog database
    format('Collecting results and printing~n',[]),
    collect_results(Dir2,_Results),

    (option('-asm')->format('*/~n',[]);true),

    pretty_print_results(Dir),
    print_stats.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% store the command line options that are valid
% fail if encounter an invalid option
:-dynamic option/1.

save_option(Arg):-
    valid_option(Arg),
    assert(option(Arg)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

decode_sections(File,Dir):-
    %collect a list with the code sections
    findall(Section,code_section(Section),Sections),
    %collect a list with the data sections
    findall(Name,data_section_descriptor(Name,_),Data_sections_names),
    %concatenate the lists into a single string
    foldl(collect_section_args(' --sect '),Sections,[],Sect_args),
    foldl(collect_section_args(' --data_sect '),Data_sections_names,[],Data_sect_args),
    atomic_list_concat(Sect_args,Section_chain),
    atomic_list_concat(Data_sect_args,Data_section_chain),
    % create command
    atomic_list_concat(['datalog_decoder ',' --file ',File,
			' --dir ',Dir,'/',Section_chain,Data_section_chain],Cmd),
    
    
    format('#cmd: ~p~n',[Cmd]),
    format(user_error,'Decoding',[]),
    time(shell(Cmd)).

    %atom_concat(Dir,'_old',Dir2),
    %(\+exists_directory(Dir2)->
    %make_directory(Dir2);true),
    %atomic_list_concat(['./datalog_decoder_old ',' --file ',File,
    %			' --dir ',Dir2,'/',Section_chain,Data_section_chain],Cmd_old),
    %format(user_error,'Old Decoding',[]),
    %time(shell(Cmd_old)).
collect_section_args(Arg,Name,Acc_sec,Acc_sec2):-
    Acc_sec2=[Arg,Name|Acc_sec].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
call_compiled_souffle(File,Dir):-
    atomic_list_concat(['souffle_disasm  ',File,' -F ',Dir,' -D ',Dir],Cmd),
    atomic_list_concat(['ddisasm  ',File,' -F ',Dir,' -D ',Dir],Cmd),
    format(user_error,'Datalog',[]),
    time(shell(Cmd)).

call_souffle(Dir):-
    atomic_list_concat(['souffle ../src/datalog/main.dl  -F ',Dir,' -D ',Dir,' -p ',Dir,'/profile'],Cmd),
    format(user_error,'Datalog',[]),
    time(shell(Cmd)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Collect the results from souffle

result_descriptors([
			  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			  %these are facts generated by the decoder
			  result(symbol,5,'.facts'),
			  result(section,3,'.facts'),
			  result(relocation,4,'.facts'),
			  result(instruction,8,'.facts'),
			  result(op_regdirect,2,'.facts'),
			  result(op_immediate,2,'.facts'),
			  result(op_indirect,7,'.facts'),
			  result(data_byte,2,'.facts'),

			  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			  %these facts are necessary for printing the asm
			  
			  % code blocks and leftover instructions
			  result(block,1,'.csv'),
			  named_result(code_in_block,'code_in_block',2,'.csv'),
			  named_result(remaining_ea,'phase2-remaining_ea',1,'.csv'),

			  %functions
			  result(function_symbol,2,'.csv'),
			  result(main_function,1,'.csv'),
			  result(start_function,1,'.csv'),
			  named_result(function_entry,'function_entry2',1,'.csv'),

			  %misc
			  result(ambiguous_symbol,1,'.csv'),
			  result(direct_call,2,'.csv'),
			  result(plt_code_reference,2,'.csv'),
			  result(plt_data_reference,2,'.csv'),
			  result(got_reference,3,'.csv'),
			  
			  %symbols in code
			  result(symbolic_operand,2,'.csv'),
			  result(moved_label,4,'.csv'),
			  
			  %labels and symbols in data
			  result(labeled_data,1,'.csv'),
			  result(symbolic_data,2,'.csv'),
			  result(symbol_minus_symbol,3,'.csv'),
			  result(moved_data_label,3,'.csv'),

			  %strings in data
			  result(string,2,'.csv'),

			  %boundaries in bss data
			  result(bss_data,1,'.csv'),
			  
		


			  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			  %these facts are only used for generating hints
			  result(stack_operand,2,'.csv'),
			  result(preferred_data_access,2,'.csv'),
			  result(data_access_pattern,4,'.csv'),

			  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
			  %these facts are only collected for printing debugging information
			  result(discarded_block,1,'.csv'),
			  result(direct_jump,2,'.csv'),
			  result(related_data_access,2,'.csv'),
			  result(pc_relative_jump,2,'.csv'),
			  result(pc_relative_call,2,'.csv'),
			  named_result(block_overlap,'block_still_overlap',2,'.csv'),
			  result(def_used,4,'.csv'),
			  result(paired_data_access,6,'.csv'),
			  result(value_reg,7,'.csv'),
			  result(incomplete_cfg,1,'.csv'),
			  result(no_return,1,'.csv'),
			  result(in_function,2,'.csv')
				
		      ]).

:-dynamic symbol/5.
:-dynamic section/3.
:-dynamic relocation/4.
:-dynamic instruction/8.
:-dynamic op_regdirect/2.
:-dynamic op_immediate/2.
:-dynamic op_indirect/7.
:-dynamic data_byte/2.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:-dynamic block/1.
:-dynamic discarded_block/1.
:-dynamic code_in_block/2.
:-dynamic remaining_ea/1.

:-dynamic function_symbol/2.
:-dynamic main_function/1.
:-dynamic start_function/1.
:-dynamic function_entry/1.

:-dynamic ambiguous_symbol/1.
:-dynamic plt_code_reference/2.
:-dynamic plt_data_reference/2.
:-dynamic got_reference/3.
:-dynamic direct_call/2.


:-dynamic symbolic_operand/2.
:-dynamic moved_label/4.

:-dynamic labeled_data/1.
:-dynamic symbolic_data/2.
:-dynamic symbol_minus_symbol/3.
:-dynamic moved_data_label/3.

:-dynamic string/2.

:-dynamic bss_data/1.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:-dynamic stack_operand/2.
:-dynamic data_access_pattern/4.
:-dynamic preferred_data_access/2.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
:-dynamic direct_jump/2.
:-dynamic pc_relative_jump/2.
:-dynamic pc_relative_call/2.
:-dynamic block_overlap/2.
:-dynamic paired_data_access/6.
:-dynamic def_used/4.
:-dynamic value_reg/7.
:-dynamic incomplete_cfg/1.
:-dynamic no_return/1.
:-dynamic in_function/2.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% read all the results in the result_descriptors and store them in the prolog database

collect_results(Dir,results(Results)):-
    result_descriptors(Descriptors),
    maplist(collect_result(Dir),Descriptors,Results).

collect_result(Dir,named_result(Name,Filename,Arity,Ending),Result):-
    atom_concat(Filename,Ending,Name_file),
    directory_file_path(Dir,Name_file,Path),
    csv_read_file(Path, Result, [functor(Name), arity(Arity),separator(0'\t)]),
    maplist(assertz,Result).

collect_result(Dir,result(Name,Arity,Ending),Result):-
    atom_concat(Name,Ending,Name_file),
    directory_file_path(Dir,Name_file,Path),
    csv_read_file(Path, Result, [functor(Name), arity(Arity),separator(0'\t)]),
    maplist(assertz,Result).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print number of facts of each kind
print_stats:-
    format('~n~n#Result statistics:~n',[]),
    result_descriptors(Descriptors),
    maplist(print_descriptor_stats,Descriptors).

print_descriptor_stats(Res):-
    (Res=result(Name,Arity,_)
     ;
     Res=named_result(Name,_,Arity,_)
    ),
    functor(Head,Name,Arity),
    findall(Head,Head,Results),
    length(Results,N),
    format(' # Number of ~p: ~p~n',[Name,N]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print the complete assembly: first the code, then the data and finally the .bss
pretty_print_results(Dir):-
    print_header,
    %print code
    get_code_blocks(Blocks),
    maplist(pp_code_block, Blocks),
    
    %print data
    get_data_sections(Data_sections),
    maplist(pp_aligned_data_section,Data_sections),
    
    %print bss
    get_bss_data(Uninitialized_data),
    %we want to make sure we don't mess up the alignment
    format('~n~n#=================================== ~n',[]),
    format('.bss~n .align 16~n',[]),
    format('#=================================== ~n~n',[]),
    maplist(pp_bss_data,Uninitialized_data),

    %generate EA hints and functions hints
    generate_hints(Dir,Data_sections,Uninitialized_data),
    generate_function_hints(Dir).


print_header:-
    option('-asm'),!,
    format('
#=================================== 
.intel_syntax noprefix
#=================================== ~n',[]),
    % introduce some displacement to fail as soon as we make any mistake (for developing)
    % but without messing up the alignment
     format('
nop
nop
nop
nop
nop
nop
nop
nop
',[]).

print_header.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% collect all the code into blocks

get_code_blocks(Blocks_with_padding):-
    %collect all the blocks
    findall(Block, block(Block),Block_addresses),
    %collect all the instructions that are not in blocks
    % if -asm we do not collect anything
    (option('-asm')->
	 Single_instructions=[]
     ;
    findall(Instruction,
	    (
		instruction(EA,Size,Prefix,Name,Opc1,Opc2,Opc3,Opc4),
                \+code_in_block(EA,_),
		remaining_ea(EA),
		get_op(Opc1,Op1),
		get_op(Opc2,Op2),
		get_op(Opc3,Op3),
		get_op(Opc4,Op4),
		Instruction=instruction(EA,Size,Prefix,Name,Op1,Op2,Op3,Op4)
	    ),Single_instructions)
    ),
    % assoc is a key-value map
    empty_assoc(Empty),
    %for each block collect its instructions
    foldl(get_block_content,Block_addresses,Empty,Map),
    % add the instructions outside blocks to the map 
    foldl(accum_instruction,Single_instructions,Map,Map2),
    %get the values of the map
    assoc_to_values(Map2,Blocks),
    
    %if we are not debugging make sure there are no overlaping blocks
    %and fill the gaps with NOPs
     (\+option('-debug')->
	  adjust_padding(Blocks,Blocks_with_padding)
      ;
      Blocks=Blocks_with_padding
     ).

get_block_content(Block_addr,Assoc,Assoc1):-
    %get the instruction in the block
    findall(Instruction,
	    (code_in_block(EA,Block_addr),
	     instruction(EA,Size,Prefix,Name,Opc1,Opc2,Opc3,Opc4),
	     get_op(Opc1,Op1),
	     get_op(Opc2,Op2),
	     get_op(Opc3,Op3),
	     get_op(Opc4,Op4),
	     Instruction=instruction(EA,Size,Prefix,Name,Op1,Op2,Op3,Op4)
	    ),Instructions),
    get_block_end_address(Instructions,Block_addr,End),
    put_assoc(Block_addr,Assoc,block(Block_addr,End,Instructions),Assoc1).


get_block_end_address([],Block_addr,Block_addr).
get_block_end_address(Instructions,_,End):-
     last(Instructions,instruction(EA_last,Size_last,_,_,_,_,_,_)),
     End is EA_last+Size_last.

% get the operators without the operator id
get_op(0,none):-!.
get_op(N,reg(Name)):-
    op_regdirect(N,Name),!.
get_op(N,immediate(Immediate)):-
    op_immediate(N,Immediate),!.
get_op(N,indirect(Reg1,Reg2,Reg3,A,B,Size)):-
    op_indirect(N,Reg1,Reg2,Reg3,A,B,Size),!.

accum_instruction(instruction(EA,Size,Prefix,OpCode,Op1,Op2,Op3,Op4),Assoc,Assoc1):-
    put_assoc(EA,Assoc,instruction(EA,Size,Prefix,OpCode,Op1,Op2,Op3,Op4),Assoc1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


adjust_padding([Last],[Last]).
adjust_padding([Block1,Block2|Blocks], Final_blocks):-
    get_begin_end(Block1,_Beg,End),
    get_begin_end(Block2,Beg2,_End2),
    (Beg2=End->
	 adjust_padding([Block2|Blocks],Blocks_adjusted),
	 Final_blocks=[Block1|Blocks_adjusted]
     ;
     Beg2>End->
	 Nop=instruction(End,1,_,'NOP',none,none,none,none),
	 adjust_padding([Nop,Block2|Blocks],Blocks_adjusted),
	 Final_blocks=[Block1|Blocks_adjusted]
     ;
     Beg2<End->
	 adjust_padding([Block1|Blocks],Blocks_adjusted),
	 Final_blocks=Blocks_adjusted
    ).

get_begin_end(block(Beg,End,_),Beg,End).
get_begin_end(instruction(Beg,Size,_,_,_,_,_,_),Beg,End):-
    End is Beg+Size.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% data types:

% Data_sections = list of data_section(Name:atom,Alignment:number,Data_groups)
% Data_groups= list of data_group(EA:address,type:atom,Content: data_group_content)
%                   or data_byte(EA:address,Byte:number)
% data_group_content can vary according to the type of the data group


% collect all the data into data_section which contain
% lists of data_groups (such as strings or pointers) or individual data_byte

get_data_sections(Data_sections):-
    findall(data_section_descriptor(Name,Alignment),
	    data_section_descriptor(Name,Alignment),
	    Data_section_descriptors),
    convlist(get_data_section,Data_section_descriptors,Data_sections).

get_data_section(data_section_descriptor(Section_name,Alignment),
		 data_section(Section_name,Alignment,Data_groups)):-
    section(Section_name,SizeSect,Base),!,
    %only consider sections that are not skipped
    \+skip_data_section(Section_name),
    %get all data bytes within the limits of the section
    End is Base+SizeSect,
    findall(data_byte(EA,Content),
	    (
		data_byte(EA,Content),
		EA>=Base,
		EA<End
	    )
	    ,Data),
    %exclude empty sections
    Data\=[],
    %group the data using the results of the analysis
    group_data(Data,Data_groups).

group_data([],[]).

group_data([data_byte(EA,_)|Rest],[data_group(EA,plt_ref,Function)|Groups]):-
    symbolic_data(EA,Content),
    plt_reference_qualified(EA,Content,Function),!,
    split_at(7,Rest,_,Rest2),
    group_data(Rest2,Groups).

group_data([data_byte(EA,_)|Rest],[data_group(EA,labeled_pointer,Group_content)|Groups]):-
    symbolic_data(EA,Group_content),
    labeled_data(EA),!,
    split_at(7,Rest,_,Rest2),
    group_data(Rest2,Groups).

group_data([data_byte(EA,_)|Rest],[data_group(EA,pointer,Group_content)|Groups]):-
    symbolic_data(EA,Group_content),!,
    split_at(7,Rest,_,Rest2),
    group_data(Rest2,Groups).

group_data([data_byte(EA,_)|Rest],[data_group(EA,labeled_pointer_diff,symbols(Symbol1,Symbol2))|Groups]):-
    symbol_minus_symbol(EA,Symbol1,Symbol2),
    labeled_data(EA),!,
    split_at(3,Rest,_,Rest2),
    group_data(Rest2,Groups).

group_data([data_byte(EA,_)|Rest],[data_group(EA,pointer_diff,symbols(Symbol1,Symbol2))|Groups]):-
    symbol_minus_symbol(EA,Symbol1,Symbol2),
    split_at(3,Rest,_,Rest2),
    group_data(Rest2,Groups).

group_data([data_byte(EA,Content)|Rest],[data_group(EA,string,String)|Groups]):-
    string(EA,End),!,
    Size is End-EA,
    split_at(Size,[data_byte(EA,Content)|Rest],Data_bytes,Rest2),
    append(String_bytes,[_],Data_bytes),
    maplist(get_data_byte_content,String_bytes,Bytes),
    clean_special_characters(Bytes,Bytes_clean),
    string_codes(String,Bytes_clean),
    group_data(Rest2,Groups).

group_data([data_byte(EA,Content)|Rest],[data_group(EA,accessed_data,Data_bytes)|Groups]):-
    preferred_data_access(EA,Ref),
    data_access_pattern(Ref,Size,_,_),Size>0,
    split_at(Size,[data_byte(EA,Content)|Rest],Data_bytes,Rest2),
    maplist(not_labeled,[data_byte(EA,Content)|Rest]),!,
    group_data(Rest2,Groups).

group_data([data_byte(EA,Content)|Rest],[data_group(EA,unknown,[data_byte(EA,Content)])|Groups]):-
    labeled_data(EA),!,
    group_data(Rest,Groups).

group_data([data_byte(EA,Content)|Rest],[data_byte(EA,Content)|Groups]):-
    group_data(Rest,Groups).


get_data_byte_content(data_byte(_,Content),Content).

not_labeled(data_byte(EA,_)):-
    \+labeled_data(EA).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% collect the .bss:
% collect the labels that have to printed and the sizes between labels

%Data_elements is a list of variable(Start:number,Size:number)

get_bss_data(Data_elements):-
    section('.bss',SizeSect,Base),
    End is Base+SizeSect,
      setof(EA,
	    EA^(
		bss_data(EA)
	     ;
	     %the last border
	     EA=End
	    )
	    ,Addresses),
      group_bss_data(Addresses,Data_elements).

get_bss_data([]):-
    \+section('.bss',_,_).

group_bss_data([],[]).
group_bss_data([Last],[variable(Last,0)]).
group_bss_data([Start,Next|Rest],[variable(Start,Size)|Rest_vars]):-
		   Size is Next-Start,
		   group_bss_data([Next|Rest],Rest_vars).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print data sections

% special case for .init_array and .fini_array
pp_aligned_data_section(data_section(Name,Required_alignment,Data_list)):-
    meta_section(Name),!,
    print_section_header(Name,Required_alignment),
    exclude(pointer_to_excluded_code,Data_list,Data_list_filtered),
    maplist(pp_data,Data_list_filtered).

pp_aligned_data_section(data_section(Name,Required_alignment,Data_list)):-
    % get first label and ensure it has the right alignment
    % possibly adding some padding
    nth0(Index,Data_list,data_group(EA,_Type,_Content)),!,
    Alignment is EA mod Required_alignment,
    Current_alignment is Index mod Required_alignment,

    get_needed_padding(Alignment,Current_alignment,Required_alignment,Required_zeros),
    print_section_header(Name),
    format('.align ~p~n',[Required_alignment]),
    format('# printing ~p extra bytes to guarantee alignment~n',[Required_zeros]),
    print_x_zeros(Required_zeros),
    (option('-stir')->
       format('# printing 16 extra bytes to shake things a little~n',[]),
           print_x_zeros(16)
     ;
     true),
    section(Name,_,Base),
    print_label(Base),
    maplist(pp_data,Data_list).


%if there are no labels
pp_aligned_data_section(data_section(Name,Required_alignment,Data_list)):-
    print_section_header(Name,Required_alignment),
    section(Name,_,Base),
    print_label(Base),
    maplist(pp_data,Data_list).

% exclude pointers to skipped sections of the code
pointer_to_excluded_code(data_group(_EA,Type,Val)):-
    (Type=labeled_pointer ; Type=pointer),
    option('-asm'),!,
    asm_skip_function(Function),
    is_in_function(Val,Function).

get_needed_padding(Alignment,Current_alignment,_,Needed_zeros):-
    Alignment>= Current_alignment,
    Needed_zeros is Alignment-Current_alignment.
get_needed_padding(Alignment,Current_alignment,Required_alignment,Needed_zeros):-
    Alignment< Current_alignment,
    Needed_zeros is (Alignment+Required_alignment)-Current_alignment.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print data groups according to the type

pp_data(data_group(EA,plt_ref,Function)):-
    print_label(EA),
    print_ea(EA),
    format('.quad ~s',[Function]),
    cond_print_comments(EA),
    print_end_label(EA,8).

pp_data(data_group(EA,pointer,Content)):-
    print_ea(EA),
    adjust_moved_data_label(EA,Content,Printed),
    format('.quad ~p',[Printed]),
    cond_print_comments(EA),
    print_end_label(EA,8).
     
pp_data(data_group(EA,labeled_pointer,Content)):-
    print_label(EA),
    print_ea(EA),
    adjust_moved_data_label(EA,Content,Printed),
    format('.quad ~p',[Printed]),
    cond_print_comments(EA),
    print_end_label(EA,8).

pp_data(data_group(EA,labeled_pointer_diff,symbols(Symbol1,Symbol2))):-
    print_label(EA),
    print_ea(EA),
    format(atom(Printed1),'.L_~16r',[Symbol1]),
    format(atom(Printed2),'.L_~16r',[Symbol2]),
    %note the order is the inverse
    format('.long ~p-~p',[Printed2,Printed1]),
    cond_print_comments(EA),
    print_end_label(EA,4).

pp_data(data_group(EA,pointer_diff,symbols(Symbol1,Symbol2))):-
    print_ea(EA),
    format(atom(Printed1),'.L_~16r',[Symbol1]),
    format(atom(Printed2),'.L_~16r',[Symbol2]),
    %note the order is the inverse
    format('.long ~p-~p',[Printed2,Printed1]),
    cond_print_comments(EA),
    print_end_label(EA,4).

pp_data(data_group(EA,string,Content)):-
    print_label(EA),
    print_ea(EA),
    set_prolog_flag(character_escapes, false),
    format('.string "~p"',[Content]),
    set_prolog_flag(character_escapes, true),
    cond_print_comments(EA),

    get_string_length(Content,Length),
    print_end_label(EA,Length).

pp_data(data_group(EA,accessed_data,Content)):-
    print_label(EA),
    maplist(pp_data,Content).

pp_data(data_group(EA,unknown,Content)):-
    print_label(EA),
    maplist(pp_data,Content).

pp_data(data_byte(EA,Content)):-
    print_ea(EA),
    format('.byte 0x~16r',[Content]),
    cond_print_comments(EA),
    print_end_label(EA,1).

% if the pointer has been moved adjust the address accordingly
adjust_moved_data_label(EA,Val,Printed):-
    (moved_data_label(EA,Val,New_val)->
	Diff is Val-New_val,
	format(atom(Printed),'.L_~16r+~p',[New_val,Diff])
    ;
    format(atom(Printed),'.L_~16r',[Val])
    ).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print bss data

pp_bss_data(variable(Start,0)):-!,
    cond_print_global_symbol(Start),
    format('.L_~16r:  ~n',[Start]).

pp_bss_data(variable(Start,Size)):-
    cond_print_global_symbol(Start),
    format('.L_~16r: .zero ~p~n',[Start,Size]).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print block of code

pp_code_block(block(EA_block,_,_List)):-
    skip_ea(EA_block),!.
pp_code_block(instruction(EA_block,_,_,_,_,_,_,_)):-
    skip_ea(EA_block),!.

pp_code_block(block(EA_block,_,List)):-
    !,
    cond_print_section_header(EA_block),
    print_function_header(EA_block),
    print_label(EA_block),   
    (option('-debug')->
	 get_comments(EA_block,Comments),
	 print_comments(Comments),nl
     ;
     true),
    maplist(pp_instruction_rand,List),nl.

pp_code_block(instruction(EA,Size,Prefix,Operation,Op1,Op2,Op3,Op4)):-
    cond_print_section_header(EA),
    pp_instruction_rand(instruction(EA,Size,Prefix,Operation,Op1,Op2,Op3,Op4)).
    

print_function_header(EA):-
    is_function(EA,Name),
    format('#----------------------------------- ~n',[]),
    %enforce maximum alignment 
    (0=:= EA mod 8 -> 
	 format('.align 8~n',[])
     ;
    0=:= EA mod 2 -> 
	format('.align 2~n',[])
     ;
     true
    ),
    format('.globl ~p~n',[Name]),
    format('.type ~p, @function~n',[Name]),
    format('~p:~n',[Name]),
    format('#----------------------------------- ~n',[]).

print_function_header(_).


function_complete_name(EA,'main'):-
    main_function(EA),!.
function_complete_name(EA,'_start'):-
    start_function(EA),!.
function_complete_name(EA,NameNew):-
    function_symbol(EA,Name),
    (ambiguous_symbol(Name)->
	 format(string(Name_complete),'~p_~16r',[Name,EA])
     ;
     Name_complete=Name
    ),
    avoid_reg_name_conflics(Name_complete,NameNew).

function_complete_name(EA,Name):-
    function_entry(EA),
    \+function_symbol(EA,_),   
    format(string(Name),'unknown_function_~16r',[EA]).


is_function(EA,Name_complete):-
    function_complete_name(EA,Name_complete).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print instructions
% this predicate print random nops before the instruction if the -stir option is given
% otherwise it just calls pp_instruction

pp_instruction_rand(Instruction):-
    option('-stir'),!,
    (maybe(1,3)->
	 random(1,10,Random),
	 repeat_n_times(format('     nop #stir ~n',[]),Random)
     ;
     true),
    pp_instruction(Instruction).
pp_instruction_rand(Instruction):-
    pp_instruction(Instruction).

%%%%%%%%%%%%%
%special cases
% some instructions operands have to be adapted or reordered
% some instruction prefixes need to be adapted

pp_instruction(instruction(EA,Size,'','NOP',none,none,none,none)):-
    repeat_n_times((print_ea(EA),format(' nop ~n',[])),Size),
    cond_print_comments(EA).

pp_instruction(instruction(EA,Size,Prefix,'MOVSD',Op1,Op2,none,none)):-
    Op1=indirect('NullReg64', 'RSI', 'NullReg64', 1, 0, 32),
    Op2=indirect('NullReg64', 'RDI', 'NullReg64', 1, 0, 32),!,
    pp_instruction(instruction(EA,Size,Prefix,'MOVSD',none,none,none,none)).

pp_instruction(instruction(EA,_Size,Prefix,String_op,Op1,none,none,none)):-
    opcode_suffix(String_op,Op_suffix),
    member(Op_suffix,['MOVS','CMPS']),!,
    print_ea(EA),
    downcase_atom(String_op,OpCode_l),
    get_op_indirect_size_suffix(Op1,Suffix),
    format('~p ~p~p',[Prefix,OpCode_l,Suffix]),
    cond_print_comments(EA).


% FDIV_TO, FMUL_TO, FSUBR_TO, etc.
pp_instruction(instruction(EA,Size,Prefix,Operation_TO,Op1,none,none,none)):-
    atom_concat(Operation,'_TO',Operation_TO),!,
    pp_instruction(instruction(EA,Size,Prefix,Operation,reg('ST'),Op1,none,none)).

pp_instruction(instruction(EA,Size,Prefix,FCMOV,Op1,none,none,none)):-
   atom_concat('FCMOV',_,FCMOV),!,
   pp_instruction(instruction(EA,Size,Prefix,FCMOV,Op1,reg('ST'),none,none)).

pp_instruction(instruction(EA,Size,Prefix,Loop,reg('RCX'),Op2,none,none)):-
    atom_concat('LOOP',_,Loop),!,
    pp_instruction(instruction(EA,Size,Prefix,Loop,none,Op2,none,none)).

pp_instruction(instruction(EA,Size,'lock',Operation,Op1,Op2,Op3,Op4)):-!,
    pp_instruction(instruction(EA,Size,'lock\n           ',Operation,Op1,Op2,Op3,Op4)).

%%%%%%%%%%%%%%%
% general case
pp_instruction(instruction(EA,_Size,Prefix,OpCode,Op1,Op2,Op3,Op4)):-

    print_ea(EA),
    downcase_atom(OpCode,OpCode_l),
    adapt_opcode(OpCode_l,OpCode_adapted),
    format('~p ~p',[Prefix,OpCode_adapted]),
    %operands
    pp_operand_list([Op1,Op2,Op3,Op4],EA,1,Pretty_ops),
    % print the operands in the order: dest, src1 src2
    (
	append(Source_operands,[Dest_operand],Pretty_ops),
	print_with_sep([Dest_operand|Source_operands],',')
     ;
        %unless there are no operands
        Pretty_ops=[]
    ),
    %conditionally print comments on the instructions
    % or just \n
    cond_print_comments(EA).

% these opcodes do not really exist
adapt_opcode(movsd2,movsd).
adapt_opcode(imul2,imul).
adapt_opcode(imul3,imul).
adapt_opcode(imul1,imul).
adapt_opcode(cmpsd3,cmpsd).
adapt_opcode(out_i,out).
adapt_opcode(Operation,Operation).

opcode_suffix(Opcode,Suffix):-
    atom_codes(Opcode,Codes),
    atom_codes(' ',[Space]),
    append(_Prefix,[Space|Suffix_codes],Codes),!,
    atom_codes(Suffix,Suffix_codes).
opcode_suffix(Opcode,Opcode).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print operands

%print the operand list to a list of strings
% keeping track of the operator number
pp_operand_list([],_EA,_N,[]).
pp_operand_list([none|Ops],EA,N,Pretty_ops):-
    N1 is N+1,
    pp_operand_list(Ops,EA,N1,Pretty_ops).
pp_operand_list([Op|Ops],EA,N,[Op_pretty|Pretty_ops]):-
    pp_operand(Op,EA,N,Op_pretty),
    N1 is N+1,
    pp_operand_list(Ops,EA,N1,Pretty_ops).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print one operand

%register
pp_operand(reg(Name),_,_,Name2):-
    adapt_register(Name,Name2).

%immediate
pp_operand(immediate(Num),EA,1,Name):-
    (
     direct_call(EA,_)
     ;
     direct_jump(EA,_)
    ),
    plt_reference_qualified(EA,Num,Name),!.

pp_operand(immediate(_Num),EA,1,Name_complete):-
    plt_code_reference(EA,Name),!,
    format(string(Name_complete),'OFFSET ~p',[Name]).


pp_operand(immediate(_Num),EA,_N,Name_complete):-
    direct_call(EA,Dest),
    (\+skip_ea(Dest)->
	 function_complete_name(Dest,Name_complete)
     ;
     Name_complete=Dest
    ).
 
pp_operand(immediate(Offset),EA,N,Num_hex):-
    moved_label(EA,N,Offset,Offset2),!,
    Diff is Offset-Offset2,
    (get_global_symbol_ref(Offset2,absolute,Name_symbol)->
	 format(string(Num_hex),'OFFSET ~p+~p',[Name_symbol,Diff])
     ;
     print_symbol(Offset2,Label),
     format(string(Num_hex),'OFFSET ~p+~p',[Label,Diff])
    ).

% special case for mov from symbolic
pp_operand(immediate(Num),EA,1,Num_hex):-
    symbolic_operand(EA,1),!,
    (get_global_symbol_ref(Num,absolute,Name_symbol)->
	 format(string(Num_hex),'OFFSET ~p',[Name_symbol])
     ;
     print_symbol(Num,Label),
     format(string(Num_hex),'OFFSET ~p',[Label])
    ).

pp_operand(immediate(Num),EA,N,Num_hex):-
    symbolic_operand(EA,N),!,
    print_symbol(Num,Num_hex).

pp_operand(immediate(Num),_,_,Num).


%indirect operand
%consider different combinations of relative addressing

pp_operand(indirect(NullSReg,NullReg1,NullReg2,1,0,Size),_,_,PP):-
    null_reg(NullSReg),
    null_reg(NullReg1),
    null_reg(NullReg2),
    get_size_name(Size,Name),
    format(atom(PP),'~p [~p]',[Name,0]).

pp_operand(indirect(_,_,_,_,_,_),EA,N,PP):-
    \+moved_label(EA,N,_,_),
    got_reference(EA,N,Content),!,
    format(atom(PP),'.L_~16r@GOTPCREL[rip]',[Content]).

% special case for rip relative addressing
pp_operand(indirect(NullSReg,'RIP',NullReg1,1,Offset,Size),EA,N,PP):-
    null_reg(NullSReg),
    null_reg(NullReg1),
    symbolic_operand(EA,N),!,
    get_size_name(Size,Name_size),
    instruction(EA,Size_instr,_,_,_,_,_,_),
    Address is EA+Offset+Size_instr,
    (moved_label(EA,N,Address,Address2)->
	 Diff is Address-Address2
     ;
     Diff=0,
     Address2=Address
    ),
    get_diff_addend(Diff,Diff_addend),
    (get_global_symbol_ref(Address2,relative,Name_symbol)->
	 true
     ;
     print_symbol(Address2,Name_symbol)
    ),
    format(atom(PP),'~p ~p~p[rip]',[Name_size,Name_symbol,Diff_addend]).

pp_operand(indirect(SReg,Reg,NullReg1,1,0,Size),_,_,PP):-
    null_reg(NullReg1),
    adapt_register(Reg,Reg_adapted),
    get_size_name(Size,Name),
    put_segment_register(Reg_adapted,SReg,Term),
    format(atom(PP),'~p ~p',[Name,Term]).

pp_operand(indirect(SReg,NullReg1,NullReg2,1,Offset,Size),EA,N,PP):-
    null_reg(NullReg1),
    null_reg(NullReg2),
    get_size_name(Size,Name),
    (get_global_symbol_ref(Offset,absolute,Name_symbol)->
	 put_segment_register(Name_symbol,SReg,Term),
	 format(atom(PP),'~p ~p',[Name,Term])
     ;
     get_offset_and_sign(Offset,EA,N,Offset1,PosNeg),
     Term=..[PosNeg,Offset1],
     put_segment_register(Term,SReg,Term_with_sreg),
     format(atom(PP),'~p ~p',[Name,Term_with_sreg])
    ).
  
pp_operand(indirect(SReg,Reg,NullReg1,1,Offset,Size),EA,N,PP):-
    null_reg(NullReg1),
    adapt_register(Reg,Reg_adapted),
    get_offset_and_sign(Offset,EA,N,Offset1,PosNeg),
    get_size_name(Size,Name),
    Term=..[PosNeg,Reg_adapted,Offset1],
    put_segment_register(Term,SReg,Term_with_sreg),
    format(atom(PP),'~p ~p',[Name,Term_with_sreg]).

pp_operand(indirect(SReg,NullReg1,Reg_index,Mult,Offset,Size),EA,N,PP):-
    null_reg(NullReg1),
    adapt_register(Reg_index,Reg_index_adapted),
    get_offset_and_sign(Offset,EA,N,Offset1,PosNeg),
    get_size_name(Size,Name),
    Term=..[PosNeg,Reg_index_adapted*Mult,Offset1],
    put_segment_register(Term,SReg,Term_with_sreg),
    format(atom(PP),'~p ~p',[Name,Term_with_sreg]).


pp_operand(indirect(SReg,Reg,Reg_index,Mult,0,Size),_,_N,PP):-
    adapt_register(Reg,Reg_adapted),
    adapt_register(Reg_index,Reg_index_adapted),
    get_size_name(Size,Name),
    put_segment_register(Reg_adapted+Reg_index_adapted*Mult,SReg,Term_with_sreg),
    format(atom(PP),'~p ~p',[Name,Term_with_sreg]).


pp_operand(indirect(SReg,Reg,Reg_index,Mult,Offset,Size),EA,N,PP):-
    adapt_register(Reg,Reg_adapted),
    adapt_register(Reg_index,Reg_index_adapted),
    get_size_name(Size,Name),
    get_offset_and_sign(Offset,EA,N,Offset1,PosNeg),
    Term=..[PosNeg,Reg_adapted+Reg_index_adapted*Mult,Offset1],
    put_segment_register(Term,SReg,Term_with_sreg),
    format(atom(PP),'~p ~p',[Name,Term_with_sreg]).


%if the label is skipped we treat it like a constant
print_symbol(Num,Num):-
    skip_ea(Num),!.

print_symbol(Num,Label):-
    format(string(Label),'.L_~16r',[Num]).

%auxiliary predicate for indirect addressing

get_offset_and_sign(Offset,EA,N,Offset1,'+'):-
    moved_label(EA,N,Offset,Offset2),!,
    Diff is Offset-Offset2,
    print_symbol(Offset2,Label),
    get_diff_addend(Diff,Diff_addend),
    format(atom(Offset1),'~p~p',[Label,Diff_addend]).

get_offset_and_sign(Offset,EA,N,Offset1,'+'):-
    symbolic_operand(EA,N),!,
    print_symbol(Offset,Label),
    format(atom(Offset1),'~p',[Label]).
get_offset_and_sign(Offset,_EA,_N,Offset1,'-'):-
    Offset<0,!,
    Offset1 is 0-Offset.
get_offset_and_sign(Offset,_EA,_N,Offset,'+').

%attach the segment register (if there is one)
put_segment_register(Term,SReg,[Term]):-
    null_reg(SReg),!.
put_segment_register(Term,SReg,SReg:[Term]).


get_diff_addend(0,'').
get_diff_addend(N,PP):-
    N>0,
    format(atom(PP),'+~p',[N]).
get_diff_addend(N,PP):-
    N<0,
    format(atom(PP),'~p',[N]).

get_size_name(128,'').
get_size_name(0,'').
get_size_name(80,'TBYTE PTR').
get_size_name(64,'QWORD PTR').
get_size_name(32,'DWORD PTR').
get_size_name(16,'WORD PTR').
get_size_name(8,'BYTE PTR').
get_size_name(Other,size(Other)).

get_op_indirect_size_suffix(indirect(_,_,_,_,_,Size),Suffix):-
    get_size_suffix(Size,Suffix).

get_size_suffix(128,'').
get_size_suffix(0,'').
get_size_suffix(64,'q').
get_size_suffix(32,'d').
get_size_suffix(16,'w').
get_size_suffix(8,'b').


adapt_register('R8L','R8B'):-!.
adapt_register('R9L','R9B'):-!.
adapt_register('R10L','R10B'):-!.
adapt_register('R11L','R11B'):-!.
adapt_register('R12L','R12B'):-!.
adapt_register('R13L','R13B'):-!.
adapt_register('R14L','R14B'):-!.
adapt_register('R15L','R15B'):-!.

adapt_register('ST0','ST(0)'):-!.
adapt_register('ST1','ST(1)'):-!.
adapt_register('ST2','ST(2)'):-!.
adapt_register('ST3','ST(3)'):-!.
adapt_register('ST4','ST(4)'):-!.
adapt_register('ST5','ST(5)'):-!.
adapt_register('ST6','ST(6)'):-!.
adapt_register('ST7','ST(7)'):-!.
adapt_register(Reg,Reg).

null_reg('NullReg64').
null_reg('NullReg32').
null_reg('NullReg16').
null_reg('NullSReg').

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% common predicates for printing data and code


cond_print_section_header(EA):-
    section(Name,_,EA),!,
    print_section_header(Name).
cond_print_section_header(_).

print_section_header('.text'):-
    format('~n~n#=================================== ~n',[]),
    format('.text~n',[]),
    format('#=================================== ~n~n',[]).

print_section_header(Name):-
    format('~n~n#=================================== ~n',[]),
    format('.section ~p~n',[Name]),
    format('#=================================== ~n~n',[]).

print_section_header(Name,Required_alignment):-
    format('~n~n#=================================== ~n',[]),
    format('.section ~p~n.align ~p~n',[Name,Required_alignment]),
    format('#=================================== ~n',[]).

% print the address if we are not in -asm mode
print_ea(_):-
    option('-asm'),!,
    format('          ',[]).

print_ea(EA):-
    format('         ~16r: ',[EA]).

print_label(EA):-
    cond_print_global_symbol(EA),
    format('.L_~16r:~n',[EA]).

print_end_label(EA,Length):-
    EA_end is EA+Length,
    labeled_data(EA_end),
    \+data_byte(EA_end,_),
    \+bss_data(EA_end),
    cond_print_global_symbol(EA_end),
    format('.L_~16r:~n',[EA_end]).

print_end_label(_,_).

cond_print_global_symbol(EA):-
    (get_global_symbol_name(EA,Name)->
	format('~p:~n',[Name])
     ;
     true
    ).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% print comments for debugging
% for each EA collect the relevant facts and print them

cond_print_comments(EA):-
       (option('-debug')->
   	 get_comments(EA,Comments),
   	 print_comments(Comments)
     ;
     true
       ),nl.

get_comments(EA_block,Comments):-
	setof(Comment,comment(EA_block,Comment),Comments),!.
get_comments(_EA_block,[]).
    
comment(EA,discarded):-
    discarded_block(EA).

comment(EA,overlap_with(Str_EA2)):-
    block_overlap(EA2,EA),
    format(string(Str_EA2),'~16r',[EA2]).

comment(EA,overlap_with(Str_EA2)):-
    block_overlap(EA,EA2),
    format(string(Str_EA2),'~16r',[EA2]).

comment(EA,is_called):-
    direct_call(_,EA).

comment(EA,jumped_from(Str_or)):-
    direct_jump(Or,EA),
    format(string(Str_or),'~16r',[Or]).

comment(EA,not_in_block):-
    \+code_in_block(EA,_).

comment(EA,symbolic_ops(Symbolic_ops)):-
    findall(Op_num,symbolic_operand(EA,Op_num),Symbolic_ops),
    Symbolic_ops\=[].

comment(EA,plt(Dest)):-
    plt_code_reference(EA,Dest).


comment(EA,pc_relative_jump(Dest_hex)):-
    pc_relative_jump(EA,Dest),
    format(atom(Dest_hex),'~16r',[Dest]).

comment(EA,used(Tuples)):-
    findall((Reg,EA_used_hex,Index),
	    (
	    def_used(EA,Reg,EA_used,Index),
	    pp_to_hex(EA_used,EA_used_hex)
	    ),
	    Tuples),
    Tuples\=[].

comment(EA,labels(Refs_hex)):-
     findall(Ref,
	    preferred_data_access(EA,Ref),
	    Refs),
     Refs\=[],
     maplist(pp_to_hex,Refs,Refs_hex).

comment(EA,values(Values_pp)):-
    findall(value_reg(EA,Reg,EA2,Reg2,Multiplier,Offset,Steps),
	    value_reg(EA,Reg,EA2,Reg2,Multiplier,Offset,Steps),
	    Values),
    Values\=[],
    maplist(pp_value_reg,Values,Values_pp).

comment(EA,access(Values_pp)):-
    findall(data_access_pattern(Size,Mult,From),
	    data_access_pattern(EA,Size,Mult,From),
	    Values),
    Values\=[],
    maplist(pp_data_access_pattern,Values,Values_pp).

comment(EA,paired_access(Values_pp)):-
    findall(paired_data_access(Size1,Multiplier,EA2,Size2),
	    paired_data_access(EA,Size1,Multiplier,EA2,Size2,_Diff),
	    Values),
    Values\=[],
    maplist(pp_paired_data_access,Values,Values_pp).

comment(EA,moved_label(Values_pp)):-
    findall(moved_label(Index,Val,New_val),
	    moved_label(EA,Index,Val,New_val),
	    Values),
    Values\=[],
    maplist(pp_moved_label,Values,Values_pp).

comment(EA,incomplete_cfg):-
	    incomplete_cfg(EA).


comment(EA,no_return):-
	    no_return(EA).

comment(EA,in_function(Functions)):-
    findall(Function_pp,(
		in_function(EA,Function),
		pp_to_hex(Function,Function_pp)				   
		),
	    Functions),
    Functions\=[].

comment(EA,related_data_access(Accesses)):-
    findall(Access_pp,(
		related_data_access(EA,Access),
		pp_to_hex(Access,Access_pp)
		),
	    Accesses),
    Accesses\=[].

comment(EA,moved_data_label):-
    moved_data_label(EA,_,_).

% auxiliary functions to pretty print the comments
    
pp_moved_label(moved_label(Index,Val,New_val),
		 moved_label(Index,Val_hex,New_val_hex)):-
    pp_to_hex(Val,Val_hex),
    pp_to_hex(New_val,New_val_hex).

pp_paired_data_access(paired_data_access(Size1,Multiplier,EA2,Size2),
		       paired_data_access(Size1,Multiplier,EA2_hex,Size2)):-
    pp_to_hex(EA2,EA2_hex).
    

pp_data_access_pattern(data_access_pattern(Size,Mult,From),
		       data_access_pattern(Size,Mult,From_hex)):-
    pp_to_hex(From,From_hex).

pp_value_reg(value_reg(EA,Reg,EA2,Reg2,Multiplier,Offset,Steps),
	     value_reg(EA_hex,Reg,EA2_hex,Reg2,Multiplier,Offset,Steps)):-
    pp_to_hex(EA,EA_hex),
    pp_to_hex(EA2,EA2_hex).

pp_to_hex(EA,EA_hex):-
    format(atom(EA_hex),'~16r',[EA]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% predicates to skip certain sections or functions added by the compiler

skip_data_section(Section_name):-
    option('-asm'),
    asm_skip_section(Section_name).


skip_ea(EA):-
    option('-asm'),
    ( asm_skip_section(Section),
      is_in_section(EA,Section)
     ;
     asm_skip_function(Function),
     is_in_function(EA,Function)
    ).

is_in_symbol(EA,Name):-
    symbol(Base,Size,_,_,Name),
    EA>=Base,
    End is Base+Size,
    EA<End.

is_in_section(EA,Name):-
    section(Name,Size,Base),
    EA>=Base,
    End is Base+Size,
    EA<End.
is_in_function(EA,Name):-
    function_get_ea(Name,EA_fun),
    % there is no function in between
    EA>=EA_fun,
    \+function_in_between(EA_fun,EA).

function_in_between(EA_fun,EA):-
	function_entry(EA_fun2),
	EA_fun2=<EA,
	EA_fun2>EA_fun.

function_get_ea('_start',EA):-
    start_function(EA),!.
function_get_ea('main',EA):-
    main_function(EA),!.
function_get_ea(Name,EA):-
    function_symbol(EA,Name).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Deal with global symbols and relocations


plt_reference_qualified(EA,_,FunctionAtPlt):-
    plt_code_reference(EA,Function),
    atom_concat(Function,'@PLT',FunctionAtPlt).
plt_reference_qualified(EA,_,FunctionAtPlt):-
    plt_data_reference(EA,Function),
    atom_concat(Function,'',FunctionAtPlt).


%check relocated symbols first
get_global_symbol_ref(Address,Relative,Final_name):-
    in_relocated_symbol(Address,Relative,Name,Offset),
    avoid_reg_name_conflics(Name,NameNew),
    (Offset\= 0->
	 Final_name=NameNew+Offset
     ;
     Final_name=NameNew).

get_global_symbol_ref(Address,_Relative,NameNew):-
    symbol(Address,_,_,'GLOBAL',Name_symbol),
    clean_symbol_name_suffix(Name_symbol,Name),
    \+reserved_symbol(Name),
    avoid_reg_name_conflics(Name,NameNew).

get_global_symbol_name(Address,NameNew):-
    symbol(Address,_,_,'GLOBAL',Name_symbol),
    %do not print labels for symbols that have to be relocated
    clean_symbol_name_suffix(Name_symbol,Name),
    \+relocation(_,_,Name,_),
    \+reserved_symbol(Name),
    avoid_reg_name_conflics(Name,NameNew).

clean_symbol_name_suffix(Name,Name_clean):-
    atom_codes(Name,Codes),
    atom_codes('@',[At]),
    append(Name_clean_codes,[At,At|_Suffix],Codes),!,
    atom_codes(Name_clean,Name_clean_codes).

clean_symbol_name_suffix(Name,Name).

in_relocated_symbol(EA,_,Name,Offset):-
%    symbol(Address,Size,_,'GLOBAL',Name_symbol),
     symbol(Address,Size,_,_,Name_symbol),
    EA>=Address,
    EA<Address+Size,
    clean_symbol_name_suffix(Name_symbol,Name),
    relocation(_,_,Name,_),
    Offset is EA-Address.
in_relocated_symbol(EA,relative,Qualified_name,Offset):-
    symbol(EA,_,_,'GLOBAL',_),
    relocation(EA,'R_X86_64_GLOB_DAT',Name,Offset),!,
    atom_concat(Name,'@GOTPCREL',Qualified_name).


% sometimes there are global symbols that have the same name of
% asm keywords so we rename them to about errors in the recompilation

avoid_reg_name_conflics(Name,NameNew):-
    reserved_name(Name),
    atom_concat(Name,'_renamed',NameNew).
avoid_reg_name_conflics(Name,Name).

reserved_name('FS').
reserved_name('MOD').
reserved_name('DIV').
reserved_name('NOT').

reserved_name('mod').
reserved_name('div').
reserved_name('not').

reserved_name('and').
reserved_name('or').


reserved_symbol(Name):-
    atom_concat('__',_Suffix,Name).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% auxiliary predicates

print_x_zeros(0).
print_x_zeros(N):-
    format('.byte 0x00~n',[]),
    N1 is N-1,
    print_x_zeros(N1).

is_none(none).

repeat_n_times(_Pred,0).
repeat_n_times(Pred,N):-
    N>0,
    call(Pred),
    N1 is N-1,
    repeat_n_times(Pred,N1).

print_comments(Comments):-
    (Comments\=[]->
	 format('          # ',[]),
	 maplist(print_with_space,Comments)
     ;true
    ).

hex_to_dec(Hex,Dec):-
    hex_bytes(Hex,Bytes),
    byte_list_to_num(Bytes,0,Dec).

byte_list_to_num([],Accum,Accum).
byte_list_to_num([Byte|Bytes],Accum,Dec):-
    Accum2 is Byte+256*Accum,
    byte_list_to_num(Bytes,Accum2,Dec).


print_with_space(Op):-
    format(' ~p ',[Op]).

print_with_sep([],_).
print_with_sep([Last],_):-
    !,
    format(' ~p',[Last]).
print_with_sep([X|Xs],Sep):-
    format(' ~p~p',[X,Sep]),
    print_with_sep(Xs,Sep).

% get rid of problematic characters in strings


clean_special_characters([],[]).
%double quote
clean_special_characters([34|Codes],[92,34|Clean_codes]):-
    !,
    clean_special_characters(Codes,Clean_codes).
% the single quote
clean_special_characters([39|Codes],[92,39|Clean_codes]):-
    !,
    clean_special_characters(Codes,Clean_codes).
%newline
clean_special_characters([10|Codes],[92,110|Clean_codes]):-
    !,
    clean_special_characters(Codes,Clean_codes).
%scape character
clean_special_characters([92|Codes],[92,92|Clean_codes]):-
    !,
    clean_special_characters(Codes,Clean_codes).

clean_special_characters([Code|Codes],[Code|Clean_codes]):-
    clean_special_characters(Codes,Clean_codes).

split_at(N,List,FirstN,Rest):-
    length(FirstN,N),
    append(FirstN,Rest,List).

get_string_length(Content,Length1):-
    atom_codes(Content,Codes),
    length(Codes,Length),
    Length1 is Length+1.% the null character

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%code to generate hints

generate_hints(Dir,Data_sections,Uninitialized_data):-
    option('-hints'),!,
    findall(Code_ea,code_in_block(Code_ea,_),Code_eas),
    directory_file_path(Dir,'hints',Path),
    open(Path,write,S),
    maplist(print_code_ea(S),Code_eas),
    maplist(print_section_data_hints(S),Data_sections),
    maplist(print_bss_data_hints(S),Uninitialized_data),
    close(S).

generate_hints(_,_,_).    

print_code_ea(S,EA):-
    format(S,'0x~16r C',[EA]),
    instruction(EA,_,_,_,Op1,Op2,Op3,Op4),
    exclude(is_zero,[Op1,Op2,Op3,Op4],Non_zero_ops),
    length(Non_zero_ops,N_ops),
    findall((Index,Type),
	    (
		symbolic_operand(EA,Index),
		Type=symbolic
	     ;
	        moved_label(EA,Index,_,_),
		Type=symbolic
	     ;
	        stack_operand(EA,Index),
	        \+symbolic_operand(EA,Index),
	        Type=stack
	    )
	    ,Indexes),
    transform_indexes(Indexes,N_ops,Indexes_tr),
    maplist(print_sym_index(S),Indexes_tr),
    format(S,'~n',[]).

is_zero(0).


transform_indexes(Indexes,N_ops,Indexes_tr):-
    foldl(transform_index(N_ops),Indexes,[],Indexes_tr).

transform_index(N_ops,(Index,Type),Accum,[(Index_tr,Type)|Accum]):-
    (Index= N_ops ->
	 Index_tr=0
     ;
     Index_tr=Index
    ).
 
print_sym_index(S,(I,symbolic)):-
    format(S,'so~p@0',[I]).
print_sym_index(S,(I,stack)):-
		 format(S,'ko~p',[I]).


print_section_data_hints(S,data_section(_Name,_Required_alignment,Data_list)):-
    group_remaining_bytes(Data_list,Data_list_grouped),
    maplist(print_element_data_hint(S),Data_list_grouped).


%for hints it is better to group the remaining bytes together with the last
% label that appeared
group_remaining_bytes([],[]).
group_remaining_bytes([data_group(EA,unknown,Content)|Rest],
		      [data_group(EA,unknown,Content2)|Rest2]):-!,
    take_contiguous_data_bytes(Rest,Data_bytes,Remaining),
    append(Content,Data_bytes,Content2),
    group_remaining_bytes(Remaining,Rest2).
group_remaining_bytes([data_group(EA,Type,Content)|Rest],[data_group(EA,Type,Content)|Rest2]):-
    group_remaining_bytes(Rest,Rest2).


group_remaining_bytes([data_byte(EA,Content)|Rest],[data_group(EA,unknown,Data_bytes)|Rest2]):-
    take_contiguous_data_bytes([data_byte(EA,Content)|Rest],Data_bytes,Remaining),
    group_remaining_bytes(Remaining,Rest2).

take_contiguous_data_bytes([],[],[]).
take_contiguous_data_bytes([data_byte(EA,Content)|Rest],[data_byte(EA,Content)|Data_bytes],Rest2):-
    take_contiguous_data_bytes(Rest,Data_bytes,Rest2).

take_contiguous_data_bytes([data_group(EA,Type,Content)|Rest],[],
			   [data_group(EA,Type,Content)|Rest]).



print_element_data_hint(S,data_group(EA,Symbolic,_)):-
    member(Symbolic,[plt_ref,pointer,labeled_pointer]),!,
    format(S,'0x~16r Dqs@0~n',[EA]).

print_element_data_hint(S,data_group(EA,string,_Content)):-
    format(S,'0x~16r D~n',[EA]).


print_element_data_hint(S,data_group(EA,accessed_data,Content)):-
    length(Content,Size),
    get_hint_size_code(Size,Code),
    format(S,'0x~16r D~p~n',[EA,Code]).


print_element_data_hint(S,data_group(EA,unknown,_Content)):-
    format(S,'0x~16r D~n',[EA]).

get_hint_size_code(8,q).
get_hint_size_code(4,d).
get_hint_size_code(2,w).
get_hint_size_code(1,b).
get_hint_size_code(_,'').


print_bss_data_hints(S,variable(EA,_)):-
      format(S,'0x~16r D~n',[EA]).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% we write two files that include or not the plt thunks
% so we can compare to different sources (swyx or debugging symbols)
generate_function_hints(Dir):-
    option('-function_hints'),!,
    findall(function_entry(EA), (function_entry(EA),EA\=0),Functions),
    sort(Functions,Functions_sorted),
    directory_file_path(Dir,'datalog_disasm_functions.txt',Path),
    open(Path,write,S),
    maplist(print_function_hint(S),Functions_sorted),
    close(S),

    exclude(in_section('.plt'),Functions_sorted,Functions2),
    exclude(in_section('.plt.got'),Functions2,Functions3),

    directory_file_path(Dir,'datalog_disasm_functions_in_text.txt',Path_in_text),
    open(Path_in_text,write,S_in_text),
    maplist(print_function_hint(S_in_text),Functions3),
    close(S_in_text).
    

generate_function_hints(_).

print_function_hint(S,function_entry(EA)):-
    format(S,'~16r~n',[EA]).

in_section(Section,function_entry(EA)):-
    section(Section,SizeSect,Base),
    EA>=Base,
    End is SizeSect+Base,
    EA<End.


% this predicate is in swi-prolog for versions after 7.5
convlist(Goal, ListIn, ListOut) :-
    convlist_(ListIn, ListOut, Goal).

convlist_([], [], _).
convlist_([H0|T0], ListOut, Goal) :-
    (   call(Goal, H0, H)
    ->  ListOut = [H|T],
        convlist_(T0, T, Goal)
    ;   convlist_(T0, ListOut, Goal)
    ).
