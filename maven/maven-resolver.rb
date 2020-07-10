#!/usr/bin/env ruby
#
# Copyright 2020 Steven Tong
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'optparse'
require "find"
require "digest"
require "net/http"
require "yaml"

p $cfg = YAML::load_file(File.expand_path(File.dirname(__FILE__))+"/maven-resolver.yaml")
REPODIR = $cfg["m2cache_dir"].strip
M2_URL = $cfg["public_url"].strip
PRIVATE_URL = $cfg["private_url"].strip
CACHEDIR = File.expand_path(File.dirname(__FILE__)) + "/cache"
PUBLICDIR = CACHEDIR + "/public/"
PRIVATEDIR = CACHEDIR + "/private/"

def download_file(filename,url)
  return if exclude?(url)
  debug "Downloaded "+filename+" from "+url
  data = Net::HTTP.get(URI.parse(url))
  if data =~ /404 Not Found/
    return
  end
  File.write(filename, data)
  debug "Downloaded "+filename
end
# get artifact attributes from m2 cache file
def get_coordinates(path)
  c = {}
  moddedpath = File.dirname(path.gsub(REPODIR,""))
  array = moddedpath.split("/")
  c[:file] = path
  c[:md5] = Digest::MD5.file(c[:file]).hexdigest
  c[:version] = array[array.size - 1]
  c[:artifactId] = array[array.size - 2]
  groupId = ""
  i = 0
  begin
    if array[i] != ""
      groupId << array[i] + "."
    end
    i += 1
  end while i < array.size - 2
  c[:groupId] = groupId.chop
  if File.basename(path) =~ /#{c[:version] + "-"}/
    c[:classifier] =  File.basename(path).split(c[:version]+"-")[1].gsub(File.extname(path),"")
  end
  c[:public_url] = M2_URL + c[:file].gsub(REPODIR,"")
  c[:private_url] = PRIVATE_URL + c[:file].gsub(REPODIR,"")
  return c
end
# get artifacts from the m2 cache
def get_maven_artifacts()
  info "Reading artifacts from local cache: "+REPODIR
  artifacts = []
  Find.find(REPODIR) do |path|
    if $cfg["extensions"].include?(File.extname(path))
      #p path
      coordinates = get_coordinates(path)
      artifacts << coordinates
    end
  end
  return artifacts
end
# helper method. is artifact created by demandtec?
def exclude?(a)
  $cfg["excludes"].each {|e|
    if a =~ /#{e}/
      return true
    end
  }
  return false
end

def get_public_md5()
  $artifacts.each {|a|
    local_file = PUBLICDIR+File.basename(a[:file])
    if !File.exists?(local_file)
      download_file(local_file,a[:public_url])
    end
    if File.exist?(local_file) 
      a[:public_md5] = Digest::MD5.file(local_file).hexdigest
      a[:public_file] = local_file
    end
  }
end
def get_private_md5()
  $artifacts.each {|a|
    local_file = PRIVATEDIR+File.basename(a[:file])
    if !File.exists?(local_file)
      download_file(local_file,a[:private_url])
    end
    if File.exist?(local_file) 
      a[:private_md5] = Digest::MD5.file(local_file).hexdigest
      a[:private_file] = local_file
    end
  }
end

def init
  `mkdir -p #{CACHEDIR}`
  `mkdir -p #{PUBLICDIR}`
  `mkdir -p #{PRIVATEDIR}`
  
  $options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: example.rb [options]"
  
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
      $options[:verbose] = v
    end
    opts.on("-s", "--show", "Show all artifacts") do |v|
      $options[:show] = v
    end
    opts.on("-d", "--diff", "Diff local m2 cache with public artifact") do |v|
      $options[:diff] = v
    end
    # public - show publically hosted artifact if md5 differs from local m2 cache
    # private - show privately hosted artifact if md5 differs from local m2 cache
    # missing_in_public - show that artifact in m2 cache doesn't exist in public repo
    opts.on("-t", "--type=TYPE", "Diff type [public|private|missing_in_public]") do |v|
      $options[:type] = v
    end    
  
  end.parse!
  
  p $options
  p ARGV
end 
init()

def main
  # get maven artifacts from local m2 cache
  $artifacts = get_maven_artifacts()
  $pub_queue = []
  get_public_md5()
  get_private_md5()
  
  if !$options[:show].nil? && $options[:show]
    $artifacts.each {|a| p a }
  end
  if !$options[:diff].nil? && $options[:diff] && $options[:type] == "public"
    $artifacts.each {|a| 
      if a[:md5] != a[:public_md5] && !exclude?(a[:file])
        p a
      end
    }
  end
  if !$options[:diff].nil? && $options[:diff] && $options[:type] == "private"
    $artifacts.each {|a| 
      if a[:md5] != a[:private_md5] && !exclude?(a[:file])
        p a
      end
    }
  end
  # so if an artifact exists in a public repository no action is needed
  # if an artifact does not exist in a public repository then,
  #   we should create a list for publishing to private repo
  if !$options[:diff].nil? && 
        $options[:diff] && 
        $options[:type] == "missing_from_public"
    info "Reporting missing from public"
    info "artifacts count: #{$artifacts.size}"
    $artifacts.each {|a| 
      puts a if a[:file] =~ /db2jcc/ || a[:file] =~ /oswego/
      if !a.has_key?(:public_file) 
        $pub_queue << a
      end
    }
    $pub_queue.each {|a|
      warning "missing from public: "+a[:file]
      p a
    }
  end
end
def warning(m)
  puts "WARNING "+m
end
def info(m)
  puts "INFO "+m
end
def debug(m)
  puts "DEBUG "+m
end
main()

