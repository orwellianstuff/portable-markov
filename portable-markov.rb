## Patent Portable Markov-in-a-box Generator
#
#  This tool generates portable Markov chain-in-a-box scripts.
#  Essentially, this program generates self-sufficient scripts that quote
#  parts from their built-in chains. They could be used as motivational tools,
#  generating endless sentences of philosophical nature and quality.
#
#  They could also be very inspirative, e.g. if you combine various types of
#  fanfiction, it could result in brand new, uncharted ideas being found.
#  It is up to you.
#
#  (c) OrwellianStuff 2018, released under MIT License
#
$GEN_PATH = File.expand_path(File.dirname(__FILE__))

require 'json'
require 'base64'
require 'zlib'
require 'date'

# Main module
module PortableMarkov

  # Markov chain class
  #
  # This class defines a structure for Markov chains
  class MarkovChain
    # Initialize a class
    # @param [Integer] level Level to use for this Markov chain
    def initialize(level)
      raise "Level must be an integer and nonzero!" unless (level.is_a?(Integer) && level > 0)
      @token_branches = Hash.new() {|hash, key| h = Hash.new(0); hash[key] = h;} # Generate a token hash, for which each nondefined entity we have an empty subhash, which returns zero
      @token_stack = [] # Stack of token identifiers

      @ids_to_translations = {} # Since tokens do not themselves convey any meaning, we store their "translations" in this hash.
      @translations_to_ids = {} # And vis a versa, since normal hashes do not have a bidirectional property

      @level = level # How many tokens' worth of recall we have?
    end

    # Finds the proper token identifier; if one doesn't exist, create a new one for it
    # @param [String] str Token to find or generate an identifier for
    def id_for_token(str)
      fstr = str.dup.freeze
      id = @translations_to_ids[fstr]

      # Nonexistent? Create a new one
      if id.nil? then
        id = (@ids_to_translations.keys.max || -1) + 1
        @ids_to_translations[id] = fstr
        @translations_to_ids[fstr] = id
      end

      return id
    end

    # Ingests an single token
    # @param [String] str Token to ingest
    def ingest_token(str)
      identifier = id_for_token(str)
      @token_stack << identifier

      if (@token_stack.length > @level)
        # We now have more tokens than our recall is.
        branch_key = @token_stack[0..-2] * ':' # Form our branch key
        branches = @token_branches[branch_key] # Check our branches
        last_token = @token_stack[-1] # Get our last token
        branches[last_token] += 1 # Add one hit

        @token_stack.shift # Remove the first token, leaving our stack in correct state again
      end
    end

    # Resets the token stack, useful for adding new files in sequence
    def reset_token_stack()
      @token_stack = []
    end

    # Generates a JSON bundle for this chain
    # @param [String] identifier Identifier/calling name
    # @return [String] JSON string
    def to_json(identifier)
      JSON::generate({"branches" => @token_branches, "name"=>identifier, "translations" => @ids_to_translations})
    end

    attr_reader :token_branches, :ids_to_translations, :level
  end

  # Writes out a runnable file for a given Markov chain
  # @param [String] json JSON-string to save
  # @param [String] file_name Filename to save to
  # @param [Boolean] save_uncompressed If true, save uncompressed
  # @param [Boolean] save_json If true, save the JSON structure as well
  def self.write_runnable_module(json, file_name, save_uncompressed, save_json)
    #runner_lines = File.readlines(File.join($GEN_PATH, "runner.rb"))
    runner_lines = DATA.each_line.to_a # Read our runner from the DATA part
    # Filter out comments
    runner_lines.map! {|x| x.strip}
    runner_lines.reject! {|x| x.start_with?("#") || x == ""}

    # Merge into a single string
    runner_merged = runner_lines * "\n"
    runner_merged.sub!("<INVALID-DATA-REPLACE-ME>", Base64.encode64(json))

    # Generate a stub for compression
    stub = <<~HEREDOC
    # Generated with Orwell's Patent Portable Markov-In-A-Box Generator, on #{DateTime.now.rfc3339}
    require 'zlib'
    require 'base64'
    $MY_FILE = __FILE__
    $COMPRESSED_RUN = true
    eval(Zlib.inflate(Base64.decode64('<COMPRESSED-HERE>')))
    HEREDOC

    # Finally, save
    File.open(file_name, "w") {|f| f.puts(save_uncompressed ? "$COMPRESSED_RUN = true;$MY_FILE = __FILE__\n"+runner_merged : stub.sub("<COMPRESSED-HERE>", Base64.encode64(Zlib::deflate(runner_merged))))}
    File.open(file_name + ".json", "w") {|f| f.puts json} if save_json
  end

  # In case we want to do token splitting, this function will be used
  # @param [String] The string to split into tokens
  # @return [Array<String>] Tokens
  def self.split_punctuation(str)
    token_stack = []
    temp_str = ""
    punctuation_marks = [".", ",", " ", "?", "!", "\n"]

    str.gsub(/ +/, " ").gsub(/[\r\n]+/, "\n").chars.each do |chr|
      if punctuation_marks.include?(chr)
        unless (temp_str.length == 0)
          token_stack << temp_str
          temp_str = ""
        end

        token_stack << chr
      else
        temp_str << chr
      end
    end

    unless (temp_str.length == 0)
      token_stack << temp_str
    end

    return token_stack
  end

  # Generates a Markov chain, according to options
  # @param [Hash] Options
  def self.generate_markov(options)
    puts "Generating a Markov generator named '#{options[:name]}', saving to file '#{options[:output_file]}', using dictionaries:"
    options[:files].each {|x| puts "\t#{x}"}
    puts "Length of #{options[:level]}, #{options[:tokenize] ? "with" : "without"} sentence tokenization, #{options[:uncompressed] ? "uncompressed" : "compressed"}"
    puts "Newlines are#{options[:strip] ? "" : " not"} stripped"
    # Initialize the Markov class
    markov = MarkovChain.new(options[:level])

    # Ingest each file
    options[:files].each do |filename|
      puts "Ingesting '#{filename}'..."
      filedata = File.read(filename)
      if options[:strip] # If stripping is on, change newlines to spaces.
        filedata.gsub!(/[\r\n]+/i, " ")
      end
      tokenized_filedata = options[:tokenize] ? split_punctuation(filedata) : filedata.chars
      tokenized_filedata.each {|k| markov.ingest_token(k)}
      options[:level].times {markov.ingest_token("")} # At the end of file, clean up by generating empty tokens
      markov.reset_token_stack() # And reset the stack finally
    end

    puts "Saving the output file#{options[:save_json] ? " and JSON" : ""}.."
    write_runnable_module(markov.to_json(options[:name]), options[:output_file], options[:uncompressed], options[:save_json])
    puts "Done!"
  end

  # Main entry point of the program
  def self.main()
    puts "Orwell's Patent Portable Markov-in-a-box Generator. Copyright OrwellianStuff 2018\n"
    options = {:output_file => nil, :name => nil, :files => [], :level => 4, :tokenize => false, :uncompressed => false, :strip => false, :save_json => false}
    if ARGV.length < 3
      puts "Usage: portable-markov.rb [options] name output_filename file1 [file2 ...]"
      puts "\t-level=<number of tokens to recall> -- How many tokens' recall we want to have?"
      puts "\t-sentences -- Shall we try to split according to sentences?"
      puts "\t-strip -- Shall newlines be stripped from the dictionaries?"
      puts "\t-uncompressed -- Save without compression?"
      puts "\t-save-json -- Save the JSON structure as well?"
      exit(1)
    end

    # Start by duplicating the ARGV table
    arglist = ARGV.dup

    # First, parse options
    while arglist.length > 0 do
      arg = arglist.shift
      if arg == "-" || !arg.start_with?("-") # Check for argument list termination
        arglist.unshift(arg) unless arg == "-" # This is fine, return this there
        break # And resume
      end

      # Does this match a level?
      if /-level=(?<level_arg>\d+)/i =~ arg
        level = level_arg.to_i
        if (level < 1)
          puts "Error: level must be greater than 0"
          exit(1)
        end

        options[:level] = level
        next # Next argument
      end

      # Simple parameters:
      shsh = {"-strip" => :strip, "-sentences" => :tokenize, "-uncompressed" => :uncompressed, "-save-json" => :save_json}

      if (val = shsh[arg]) != nil
        options[val] = true
        next
      end

      puts "Invalid argument: #{arg}"
      exit(2)
    end

    if arglist.length < 3
      puts "You MUST specify at least 3 more parameters: name, output file, and a dictionary!"
    end

    # Now, we only have the ID name and files left
    options[:name] = arglist.shift.strip
    if options[:name].length < 1
      puts "Your name must be nonempty!"
      exit(4)
    end
    options[:output_file] = arglist.shift # Take the first one as an output file

    # Check that each input file does infact exist
    arglist.each do |dictionary_file|
      if (!File.exist?(dictionary_file) || File.directory?(dictionary_file))
        puts "Dictionary '#{dictionary_file}' does not exist or is a directory!"
        exit(3)
      end

      options[:files] << dictionary_file
    end

    # Everything seems fine
    generate_markov(options)
  end
end

PortableMarkov::main() if __FILE__==$0
__END__
## Portable Markov-in-a-box Generator - Runner
#
#  This file is the runner part for the generator. Observe that all lines beginning with a # will be stripped entirely, to save
#  valuable space!
#
require 'json'
require 'base64'
module PMRunner

  # Measuring print; once the limit is up, cut output
  # @param <Hash> limits Limits to abide and subtract
  # @param <String> str String to print
  def self.measuring_print(limits, str)
    # Take measures
    rwl = str.length
    slen = str.chars.select {|x| [".", ",", "!", "?"].include?(x)}.length

    # Print the string
    print str

    # Subtract..
    limits[:sentences] -= slen unless limits[:sentences] == nil
    limits[:raw_length] -= rwl unless limits[:raw_length] == nil

    # .. did we go over the limit? Throw!
    throw(:over_limit) if limits.values.reject {|x| x.nil?}.any? {|val| val < 0}
  end

  # Once our limits have been determined, start printing. It happens here
  # @param <Hash> Limitations to obey
  # @param <Hash> JSON data structure to print with
  def self.print_random_sentences(orig_limits, json)
    catch(:over_limit) do
      limits = orig_limits.dup

      # Initialize a state, and print it out.
      state = json["branches"].keys.sample
      measuring_print limits, state.split(":").map {|x| json["translations"][x]}.reduce(:+)

      loop do
        next_state = json["branches"][state]
        next_index = next_state == nil ? nil : next_state.keys.map {|key| Array.new(json["branches"][state][key], key)}.flatten.sample
        # It may occur that we run out of possibilities. No panic then though
        # Simply recurse again, whilst retaining our current limit
        if next_index == nil
          print_random_sentences(limits, json)
          return
        end

        # Alright, we have a key.
        # Print out its translation
        measuring_print limits, json["translations"][next_index]

        # Then recompose our state string
        state = state.split(":")[1..-1].push(next_index) * ":"
      end
    end
    puts ""
  end

  # Once our data has been decoded, we enter this function
  # @param <Hash> Decoded JSON data
  def self.entrypoint(json)
    # In this JSON file, we expect to find: translations, branches, and name
    # Check if we have valid arguments
    set_sentences = nil
    set_raw_len = nil
    error = false

    # If no arguments, set sane defaults
    if ARGV.empty?
      set_sentences = 5
      set_raw_len = 140
    end

    # Go through arguments
    ARGV.each do |arg|
      # Note, magic variable assignment happens here!
      if /(?<sentence_limit>\d+)s/i =~ arg
        if (set_sentences != nil)
          error = true
          puts "Duplicate definition, define sentence limit only once."
          break
        else
          set_sentences = sentence_limit.to_i
          if set_sentences < 1
            error = true
            puts "Sentence limit must be more than 0"
          end
        end
      end
      # .. and also here!
      if /(?<raw_limit>\d+)c/i =~ arg
        if (set_raw_len != nil)
          error = true
          puts "Duplicate definition, define raw limit only once."
          break
        else
          set_raw_len = raw_limit.to_i
          if set_raw_len < 1
            error = true
            puts "Raw limit must be more than 0"
          end
        end
      end
    end

    # Check for errors or undefined
    exit(2) if (error)
    if (set_raw_len == nil && set_sentences == nil)
      puts "Use #{json["name"]} like: ruby #{$MY_FILE} <sentence limit>s <raw character limit>c"
      exit(1)
    end

    print_random_sentences({:sentences => set_sentences, :raw_length => set_raw_len}, json)
  end
end

# Usually, this should not be ran as a program - but if a special flag is set, then do so
PMRunner.entrypoint(JSON.parse(Base64.decode64("<INVALID-DATA-REPLACE-ME>"))) if $COMPRESSED_RUN == true
