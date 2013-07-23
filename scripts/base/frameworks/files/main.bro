##! An interface for driving the analysis of files, possibly independent of
##! any network protocol over which they're transported.

@load base/bif/file_analysis.bif
@load base/frameworks/analyzer
@load base/frameworks/logging
@load base/utils/site

module Files;

export {
	redef enum Log::ID += {
		## Logging stream for file analysis.
		LOG
	};

	## A structure which represents a desired type of file analysis.
	type AnalyzerArgs: record {
		## An event which will be generated for all new file contents,
		## chunk-wise.  Used when *tag* is
		## :bro:see:`Files::ANALYZER_DATA_EVENT`.
		chunk_event: event(f: fa_file, data: string, off: count) &optional;

		## An event which will be generated for all new file contents,
		## stream-wise.  Used when *tag* is
		## :bro:see:`Files::ANALYZER_DATA_EVENT`.
		stream_event: event(f: fa_file, data: string) &optional;
	} &redef;

	## Contains all metadata related to the analysis of a given file.
	## For the most part, fields here are derived from ones of the same name
	## in :bro:see:`fa_file`.
	type Info: record {
		## The time when the file was first seen.
		ts: time &log;

		## An identifier associated with a single file.
		fuid: string &log;

		## If this file was transferred over a network
		## connection this should show the host or hosts that
		## the data sourced from.
		tx_hosts: set[addr] &log;

		## If this file was transferred over a network
		## connection this should show the host or hosts that
		## the data traveled to.
		rx_hosts: set[addr] &log;

		## Connection UIDS over which the file was transferred.
		conn_uids: set[string] &log;

		## An identification of the source of the file data.  E.g. it may be
		## a network protocol over which it was transferred, or a local file
		## path which was read, or some other input source.
		source: string &log &optional;

		## A value to represent the depth of this file in relation 
		## to its source.  In SMTP, it is the depth of the MIME
		## attachment on the message.  In HTTP, it is the depth of the
		## request within the TCP connection.
		depth: count &default=0 &log;

		## A set of analysis types done during the file analysis.
		analyzers: set[string] &log;

		## A mime type provided by libmagic against the *bof_buffer*, or
		## in the cases where no buffering of the beginning of file occurs,
		## an initial guess of the mime type based on the first data seen.
		mime_type: string &log &optional;

		## A filename for the file if one is available from the source
		## for the file.  These will frequently come from 
		## "Content-Disposition" headers in network protocols.
		filename: string &log &optional;

		## The duration the file was analyzed for.
		duration: interval &log &default=0secs;

		## If the source of this file is a network connection, this field
		## indicates if the data originated from the local network or not as
		## determined by the configured bro:see:`Site::local_nets`.
		local_orig: bool &log &optional;

		## If the source of this file is a network connection, this field
		## indicates if the file is being sent by the originator of the connection
		## or the responder.
		is_orig: bool &log &optional;

		## Number of bytes provided to the file analysis engine for the file.
		seen_bytes: count &log &default=0;

		## Total number of bytes that are supposed to comprise the full file.
		total_bytes: count &log &optional;

		## The number of bytes in the file stream that were completely missed
		## during the process of analysis e.g. due to dropped packets.
		missing_bytes: count &log &default=0;

		## The number of not all-in-sequence bytes in the file stream that
		## were delivered to file analyzers due to reassembly buffer overflow.
		overflow_bytes: count &log &default=0;

		## Whether the file analysis timed out at least once for the file.
		timedout: bool &log &default=F;

		## Identifier associated with a container file from which this one was
		## extracted as part of the file analysis.
		parent_fuid: string &log &optional;
	} &redef;

	## A table that can be used to disable file analysis completely for
	## any files transferred over given network protocol analyzers.
	const disable: table[Files::Tag] of bool = table() &redef;

	## The salt concatenated to unique file handle strings generated by
	## :bro:see:`get_file_handle` before hashing them in to a file id
	## (the *id* field of :bro:see:`fa_file`).
	## Provided to help mitigate the possiblility of manipulating parts of
	## network connections that factor in to the file handle in order to
	## generate two handles that would hash to the same file id.
	const salt = "I recommend changing this." &redef;

	## Sets the *timeout_interval* field of :bro:see:`fa_file`, which is
	## used to determine the length of inactivity that is allowed for a file
	## before internal state related to it is cleaned up.  When used within a
	## :bro:see:`file_timeout` handler, the analysis will delay timing out
	## again for the period specified by *t*.
	##
	## f: the file.
	##
	## t: the amount of time the file can remain inactive before discarding.
	##
	## Returns: true if the timeout interval was set, or false if analysis
	##          for the *id* isn't currently active.
	global set_timeout_interval: function(f: fa_file, t: interval): bool;

	## Adds an analyzer to the analysis of a given file.
	##
	## f: the file.
	##
	## args: the analyzer type to add along with any arguments it takes.
	##
	## Returns: true if the analyzer will be added, or false if analysis
	##          for the *id* isn't currently active or the *args*
	##          were invalid for the analyzer type.
	global add_analyzer: function(f: fa_file, 
	                              tag: Files::Tag, 
	                              args: AnalyzerArgs &default=AnalyzerArgs()): bool;

	## Removes an analyzer from the analysis of a given file.
	##
	## f: the file.
	##
	## args: the analyzer (type and args) to remove.
	##
	## Returns: true if the analyzer will be removed, or false if analysis
	##          for the *id* isn't currently active.
	global remove_analyzer: function(f: fa_file, tag: Files::Tag, args: AnalyzerArgs): bool;

	## Stops/ignores any further analysis of a given file.
	##
	## f: the file.
	##
	## Returns: true if analysis for the given file will be ignored for the
	##          rest of it's contents, or false if analysis for the *id*
	##          isn't currently active.
	global stop: function(f: fa_file): bool;

	## Translates an file analyzer enum value to a string with the analyzer's name.
	##
	## tag: The analyzer tag.
	##
	## Returns: The analyzer name corresponding to the tag.
	global analyzer_name: function(tag: Files::Tag): string;

	## Provides a text description regarding metadata of the file.
	## For example, with HTTP it would return a URL.
	##
	## f: The file to be described.
	##
	## Returns a text description regarding metadata of the file.
	global describe: function(f: fa_file): string;

	type ProtoRegistration: record {
		## A callback to generate a file handle on demand when
		## one is needed by the core.
		get_file_handle: function(c: connection, is_orig: bool): string;
		
		## A callback to "describe" a file.  In the case of an HTTP
		## transfer the most obvious description would be the URL.
		## It's like an extremely compressed version of the normal log.
		describe: function(f: fa_file): string
				&default=function(f: fa_file): string { return ""; };
	};

	## Register callbacks for protocols that work with the Files framework.  
	## The callbacks must uniquely identify a file and each protocol can 
	## only have a single callback registered for it.
	## 
	## tag: Tag for the protocol analyzer having a callback being registered.
	##
	## reg: A :bro:see:`ProtoRegistration` record.
	##
	## Returns: true if the protocol being registered was not previously registered.
	global register_protocol: function(tag: Analyzer::Tag, reg: ProtoRegistration): bool;

	## Register a callback for file analyzers to use if they need to do some manipulation
	## when they are being added to a file before the core code takes over.  This is 
	## unlikely to be interesting for users and should only be called by file analyzer
	## authors but it *not required*.
	## 
	## tag: Tag for the file analyzer.
	##
	## callback: Function to execute when the given file analyzer is being added.
	global register_analyzer_add_callback: function(tag: Files::Tag, callback: function(f: fa_file, args: AnalyzerArgs));

	## Event that can be handled to access the Info record as it is sent on
	## to the logging framework.
	global log_files: event(rec: Info);
}

redef record fa_file += {
	info: Info &optional;
};

redef record AnalyzerArgs += {
	# This is used interally for the core file analyzer api.
	tag: Files::Tag &optional;
};

# Store the callbacks for protocol analyzers that have files.
global registered_protocols: table[Analyzer::Tag] of ProtoRegistration = table();

global analyzer_add_callbacks: table[Files::Tag] of function(f: fa_file, args: AnalyzerArgs) = table();

event bro_init() &priority=5
	{
	Log::create_stream(Files::LOG, [$columns=Info, $ev=log_files]);
	}

function set_info(f: fa_file)
	{
	if ( ! f?$info )
		{
		local tmp: Info = Info($ts=f$last_active,
		                       $fuid=f$id);
		f$info = tmp;
		}

	if ( f?$parent_id )
		f$info$parent_fuid = f$parent_id;
	if ( f?$source )
		f$info$source = f$source;
	f$info$duration = f$last_active - f$info$ts;
	f$info$seen_bytes = f$seen_bytes;
	if ( f?$total_bytes ) 
		f$info$total_bytes = f$total_bytes;
	f$info$missing_bytes = f$missing_bytes;
	f$info$overflow_bytes = f$overflow_bytes;
	if ( f?$is_orig )
		f$info$is_orig = f$is_orig;
	if ( f?$mime_type ) 
		f$info$mime_type = f$mime_type;
	}

function set_timeout_interval(f: fa_file, t: interval): bool
	{
	return __set_timeout_interval(f$id, t);
	}

function add_analyzer(f: fa_file, tag: Files::Tag, args: AnalyzerArgs): bool
	{
	# This is to construct the correct args for the core API.
	args$tag = tag;
	add f$info$analyzers[Files::analyzer_name(tag)];

	if ( tag in analyzer_add_callbacks )
		analyzer_add_callbacks[tag](f, args);

	if ( ! __add_analyzer(f$id, args) )
		{
		Reporter::warning(fmt("Analyzer %s not added successfully to file %s.", tag, f$id));
		return F;
		}
	return T;
	}

function register_analyzer_add_callback(tag: Files::Tag, callback: function(f: fa_file, args: AnalyzerArgs))
	{
	analyzer_add_callbacks[tag] = callback;
	}

function remove_analyzer(f: fa_file, tag: Files::Tag, args: AnalyzerArgs): bool
	{
	args$tag = tag;
	return __remove_analyzer(f$id, args);
	}

function stop(f: fa_file): bool
	{
	return __stop(f$id);
	}

function analyzer_name(tag: Files::Tag): string
	{
	return __analyzer_name(tag);
	}

event file_new(f: fa_file) &priority=10
	{
	set_info(f);
	}

event file_over_new_connection(f: fa_file, c: connection, is_orig: bool) &priority=10
	{
	set_info(f);
	add f$info$conn_uids[c$uid];
	local cid = c$id;
	add f$info$tx_hosts[f$is_orig ? cid$orig_h : cid$resp_h];
	if( |Site::local_nets| > 0 )
		f$info$local_orig=Site::is_local_addr(f$is_orig ? cid$orig_h : cid$resp_h);

	add f$info$rx_hosts[f$is_orig ? cid$resp_h : cid$orig_h];
	}

event file_timeout(f: fa_file) &priority=10
	{
	set_info(f);
	f$info$timedout = T;
	}

event file_state_remove(f: fa_file) &priority=10
	{
	set_info(f);
	}

event file_state_remove(f: fa_file) &priority=-10
	{
	Log::write(Files::LOG, f$info);
	}

function register_protocol(tag: Analyzer::Tag, reg: ProtoRegistration): bool
	{
	local result = (tag !in registered_protocols);
	registered_protocols[tag] = reg;
	return result;
	}

function describe(f: fa_file): string
	{
	local tag = Analyzer::get_tag(f$source);
	if ( tag !in registered_protocols )
		return "";

	local handler = registered_protocols[tag];
	return handler$describe(f);
	}

event get_file_handle(tag: Analyzer::Tag, c: connection, is_orig: bool) &priority=5
	{
	if ( tag !in registered_protocols )
		return;

	local handler = registered_protocols[tag];
	set_file_handle(handler$get_file_handle(c, is_orig));
	}
