#!/usr/bin/env ruby

REPODIR = "/Users/stong/.m2/repository"

require "find"
require "digest"
require "net/http"

def download_file(a)
  File.write(filename, Net::HTTP.get(URI.parse(url))
end

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
  return c
end

def get_maven_artifacts()
  artifacts = []
  Find.find(REPODIR) do |path|
    if File.extname(path) == ".jar"
      p coordinates = get_coordinates(path)
      artifacts << coordinates
    end
  end
  return artifacts
end

artifacts = get_maven_artifacts()

artifacts.each {|a|
  p a

}
