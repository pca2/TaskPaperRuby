#!/usr/bin/ruby

class TaskPaperItem
	TYPE_NULL = 0
	TYPE_TASK = 1
	TYPE_PROJECT = 2
	TYPE_NOTE = 3
	
	LINEBREAK_UNIX = "\n" # Unix, Linux, and Mac OS X
	LINEBREAK_MAC = "\r" # classic Mac OS 9 and older
	LINEBREAK_WINDOWS = "\r\n" # DOS and Windows
	
	@@linebreak = LINEBREAK_UNIX
	@@tab_size = 4 # Number of spaces used per indentation level (if tabs aren't used)
	
	# If you want to inspect and debug these, may I suggest https://regex101.com ?
	@@tab_regexp = /^(?:\t|\ {#{@@tab_size}})+/io
	@@project_regexp = /^(?>\s*)(?>[^-].*?:)(\s*@\S+)*\s*$/i
	@@tag_regexp = /\B@((?>[a-zA-Z0-9\.\-_]+))(?:\((.*?(?<!\\))\))?/i
	@@uri_regexp = /([a-zA-Z0-9\-_\+\.]+:(?:\/\/)?(?:[a-zA-Z0-9\-_\.\+]+)(?::[a-zA-Z0-9\-_\.\+]+)*@?(?:[a-zA-Z0-9\-]+\.){1,}[a-zA-Z]{2,}(?::\d+)?(?:[\/\?]\S*)?)/i
	@@email_regexp = /([a-zA-Z0-9\-\_\+\.]+\@\S+\.\S+)/i
	@@domain_regexp = /((?<!@)\b(?:[a-zA-Z0-9\-]+\.){1,}[a-zA-Z]{2,}(?::\d+)?(?:[\/\?]\S*)?)/i
	@@link_regexp = /#{@@uri_regexp}|#{@@email_regexp}|#{@@domain_regexp}/io
	
	attr_reader :children, :type, :tags, :links
	attr_accessor :parent, :content, :extra_indent
	
	class << self
		attr_accessor :linebreak, :tab_size
	end

	def self.leading_indentation_length(line)
		# Returns character-length of leading tab/space indentation in line
		indent_len = 0
		match = @@tab_regexp.match(line)
		if match
			indent_len = match[0].length
		end
		return indent_len
	end
	
	def self.leading_indentation_levels(line)
		# Returns number of leading tab/space indentation levels in WHITESPACE-ONLY line
		num_tab_indents = line.scan(/\t/).length
		num_space_indents = line.scan(/\ {#{@@tab_size}}/o).length
		return num_tab_indents + num_space_indents
	end

	def initialize(content)
		# Instance variables
		if content
			@content = content.gsub(/[\r\n]+/, '') # full text of item, without linebreak
		end
		
		@type = TYPE_NULL
		@tags = [] # of {'name', 'value', 'range', 'type':"tag"} tags
		@links = [] # of {'text', 'url', 'range', 'type':"link"} links; range is within self.content
		@children = []
		@parent = nil
		@extra_indent = 0
		
		if @content
			parse
		end
	end
	
	def parse
		# Parse @content to populate our instance variables
		
		# Leading indentation
		content_start = TaskPaperItem.leading_indentation_length(@content)
		if content_start > 0
			@extra_indent += TaskPaperItem.leading_indentation_levels(@content[0..content_start])
		end
		
		# Type of item
		if @content.start_with?("- ", "* ")
			@type = TYPE_TASK
		elsif @@project_regexp =~ @content
			@type = TYPE_PROJECT
		else
			@type = TYPE_NOTE
		end
		
		# Tags
		@tags = []
		tag_matches = @content.to_enum(:scan, @@tag_regexp).map { Regexp.last_match }
		tag_matches.each do |match|
			name = match[1]
			value = ""
			if match[2]
				value = match[2]
			end
			range = Range.new(match.begin(0), match.end(0), true)
			@tags.push({name: name, value: value, range: range, type: "tag"})
		end
		
		# Links
		@links = []
		link_matches = @content.to_enum(:scan, @@link_regexp).map { Regexp.last_match }
		link_matches.each do |match|
			text = match[0]
			if match[1] != nil #uri
				url = text
			elsif match[2] != nil # email
				url = "mailto:#{text}"
			else # domain
				url = "http://#{text}"
			end
			range = Range.new(match.begin(0), match.end(0), true)
			@links.push({text: text, url: url, range: range, type: "link"})
		end
	end
	private :parse
	
	def content=(value)
		@content = (value) ? value : ""
		parse
	end
	
	def level
		# Depth in hierarchy, regardless of extra indentation
		if @type == TYPE_NULL and !@parent
			return -1
		end
		
		level = 0
		ancestor = @parent
		while ancestor != nil and not (ancestor.type == TYPE_NULL and ancestor.parent == nil)
			level += 1
			ancestor = ancestor.parent
		end
		
		return level
	end
	
	def effective_level
		# Actual (visual) indentation level
		parent_indent = -2 # nominal parent of root (-1) item
		if @parent
			parent_indent = @parent.effective_level
		end
		return parent_indent + 1 + @extra_indent
	end
	
	def add_child(child)
		@children.push(child)
		child.parent = self
	end
	
	def title
		if @type == TYPE_PROJECT
			return @content[0..@content.index(':') - 1]
		elsif @type == TYPE_TASK
			return @content[2..-1]
		else
			return @content
		end
	end
	
	def md5_hash
		require 'digest/md5'
		return Digest::MD5.hexdigest(@content)
	end
	
	def id_attr
		id = title
		
		metadata.each do |x|
			if x[:type] == "tag"
				val_str = (x[:value] != "") ? "(#{x[:value]})" : ""
				id = id.gsub("#{x[:name]}#{val_str}", '')
			elsif x[:type] == "link"
				id = id.gsub("#{x[:text]}", '')
			end
		end
		
		id = id.strip.downcase.gsub(/(&|&amp;)/, ' and ').gsub(/[\s\.\/\\]/, '-').gsub(/[^\w-]/, '').gsub(/[-_]{2,}/, '-').gsub(/^[-_]/, '').gsub(/[-_]$/, '')
		
		if id == ""
			# No content left after stripping tags, links, and special characters.
			# We'll use an MD5 hash of the full line.
			id = md5_hash
		end
		
		return id
	end
	
	def metadata
		# Return unified array of tags and links, ordered by position in line
		metadata = @tags + @links
		return metadata.sort_by { |e| e[:range].begin }
	end
	
	def type_name
		if @type == TYPE_PROJECT
			return "Project"
		elsif  @type == TYPE_TASK
			return "Task"
		elsif  @type == TYPE_NOTE
			return "Note"
		else
			return "Null"
		end
	end
	
	def to_s
		return @content
	end
	
	def inspect
		output = "[#{(self.effective_level)}] #{self.type_name}: #{self.title}"
		if @tags.length > 0
			output += " tags: #{@tags}"
		end
		if @links.length > 0
			output += " links: #{@links}"
		end
		if @children.length > 0
			output += " [#{@children.length} child#{(@children.length == 1) ? "" : "ren"}]"
		end
		if self.done?
			output += " [DONE]"
		end
		return output
	end
	
	def tag_value(name)
		# Returns value of tag 'name', or empty string if either the tag exists but has no value, or the tag doesn't exist at all.
		
		value = ""
		tag = @tags.find {|x| x[:name].downcase == name}
		if tag
			value = tag[:value]
		end
		
		return value
	end
	
	def has_tag?(name)
	 	return (@tags.find {|x| x[:name].downcase == name} != nil)
	end
	
	def done?
		return has_tag?("done")
	end
	
	def set_done(val)
		is_done = done?
		if val == true and !is_done
			set_tag("done")
		elsif val == false and is_done
			remove_tag("done")
		end
	end
	
	def toggle_done
		set_done(!(done?))
	end
	
	def tag_string(name, value = "")
		val = (value != "") ? "(#{value})" : ""
		return "@#{name}#{val}"
	end
	
	def set_tag(name, value = "")
		# If tag doesn't already exist, add it at the end of content.
		# If tag does exist, replace its range with new form of the tag via tag_string.
		value = (value != nil) ? value : ""
		new_tag = tag_string(name, value)
		if has_tag?(name)
			tag = @tags.find {|x| x[:name].downcase == name}
			@content[tag[:range]] = new_tag
		else
			@content += " #{new_tag}"
		end
		parse
	end
	
	def remove_tag(name)
		if has_tag?(name)
			# Use range(s), in reverse order.
			@tags.reverse.each do |tag|
				if tag[:name] == name
					range = tag[:range]
					whitespace_regexp = /\s/i
					content_len = @content.length
					tag_start = range.begin
					tag_end = range.end
					whitespace_before = (tag_start > 0 and (whitespace_regexp =~ @content[tag_start - 1]) != nil)
					whitespace_after = (tag_end < content_len - 1 and (whitespace_regexp =~ @content[tag_end]) != nil)
					if whitespace_before and whitespace_after
						# If tag has whitespace before and after, also remove the whitespace before.
						range = Range.new(tag_start - 1, tag_end, true)
					elsif tag_start == 0 and whitespace_after
						# If tag is at start of line and has whitespace after, also remove the whitespace after.
						range = Range.new(tag_start, tag_end + 1, true)
					elsif tag_end == content_len - 1 and whitespace_before
						# If tag is at end of line and has whitespace before, also remove the whitespace before.
						range = Range.new(tag_start - 1, tag_end, true)
					end
					@content[range] = ""
				end
			end
			parse
		end
	end

	def to_structure(include_titles = true)
		# Indented text output with items labelled by type, and project/task decoration stripped
		
		# Output own content, then children
		output = ""
		if @type != TYPE_NULL
			suffix = (include_titles) ? " #{title}" : ""
			output += "#{"\t" * (self.effective_level)}[#{type_name}]#{suffix}#{@@linebreak}"
		end
		@children.each do |child|
			output += child.to_structure(include_titles)
		end
		return output
	end
	
	def to_tags(include_values = true)
		# Indented text output with just item types, tags, and values
		
		# Output own content, then children
		output = ""
		if @type != TYPE_NULL
			output += "#{"\t" * (self.effective_level)}[#{type_name}] "
			if @tags.length > 0
				@tags.each_with_index do |tag, index|
					output += "@#{tag[:name]}"
					if include_values and tag[:value].length > 0
						output += "(#{tag[:value]})"
					end
					if index < @tags.length - 1
						output += ", "
					end
				end
			else
				output += "(none)"
			end
			output += "#{@@linebreak}"
		end
		@children.each do |child|
			output += child.to_tags(include_values)
		end
		return output
	end
	
	def to_links(add_missing_protocols = true)
		# Text output with just item links
		
		# Bare domains (domain.com) or email addresses (you@domain.com) are included; the add_missing_protocols parameter will prepend "http://" or "mailto:" as appropriate.
		
		# Output own content, then children
		output = ""
		if @type != TYPE_NULL
			if @links.length > 0
				key = (add_missing_protocols) ? :url : :text
				@links.each do |link|
					output += "#{link[key]}#{@@linebreak}"
				end
			end
		end
		@children.each do |child|
			output += child.to_links(add_missing_protocols)
		end
		return output
	end
	
	def to_text
		# Indent text output of original content, with normalised (tab) indentation
		
		# Output own content, then children
		output = ""
		if @type != TYPE_NULL
			output += "#{"\t" * (self.effective_level)}#{@content}#{@@linebreak}"
		end
		@children.each do |child|
			output += child.to_text
		end
		return output
	end
end