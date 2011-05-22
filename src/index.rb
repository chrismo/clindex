# $Id: index.rb,v 1.14 2003/05/28 22:57:28 chrismo Exp $
=begin
----------------------------------------------------------------------------
Copyright (c) 2002, Chris Morris
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the names Chris Morris, cLabs nor the names of contributors to
this software may be used to endorse or promote products derived from this
software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ``AS
IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
----------------------------------------------------------------------------
(based on BSD Open Source License)
=end

require 'thread'
require 'drb'
require 'cl/util/console'

# create a batch_add method? This would allow a whole
# page full of terms to be queued and the index
# locked for the duration to prevent a concurrent
# query from getting a partial result
class ClIndex
  attr_accessor :index

  WAIT = true
  NO_WAIT = false

  def initialize(verboseServer=false)
    @index = {}
    @lockMgr = ClIndexLockMgr.new
    @verboseServer = verboseServer
  end

  def assign(src)
    @index = src.index
  end

  # refactor with do_read?
  def do_edit(wait)
    locked = lock(ClIndexLockMgr::EDIT, wait)
    if locked
      begin
        yield if block_given?
      ensure
        unlock(ClIndexLockMgr::EDIT)
      end
    end
  end

  def add(term, reference, wait=NO_WAIT)
    success = false
    do_edit(wait) {
      @index[term] = [] if @index[term].nil?
      @index[term] << reference
      @index[term].uniq!
      success = true
    }
    success
  end

  def remove(reference, wait=NO_WAIT)
    success = false
    do_edit(wait) {
      @index.each_pair do |term, refArray|
        @index[term].delete(reference) if refArray.include?(reference)
        @index.delete(term) if @index[term].empty?
      end
      success = true
    }
    success
  end

  # two optional parameters, filename (defaults to index.dat in pwd) and
  # wait (defaults to false). If wait is false and a blocking action
  # is preventing saving, the call returns immediately. If wait is true,
  # save waits for the blocking action to complete before continuing.
  def save(filename='index.dat', wait=NO_WAIT)
    locked = lock(ClIndexLockMgr::SAVE, wait)
    if locked
      begin
        File.open(filename, File::CREAT|File::TRUNC|File::RDWR) do |f|
          Marshal.dump(self, f)
        end
      ensure
        unlock(ClIndexLockMgr::SAVE)
      end
    end
    locked
  end

  def load(filename='index.dat', wait=NO_WAIT)
    locked = lock(ClIndexLockMgr::LOAD, wait)
    if locked
      begin
        src = nil
        File.open(filename) do |f|
          src = Marshal.load(f)
        end
        assign(src)
      ensure
        unlock(ClIndexLockMgr::LOAD)
      end
    end
    locked
  end

  def search(term, hits, wait=NO_WAIT)
    puts 'searching...' if @verboseServer
    success = false
    do_read(wait) {
      success = true
      terms = @index.keys.grep(/#{term}/i)
      terms.each do |thisTerm|
        hits << @index[thisTerm]
      end
      hits = hits.flatten.uniq.sort
    }
    success
  end

  def do_read(wait)
    locked = lock(ClIndexLockMgr::READ, wait)
    if locked
      begin
        yield if block_given?
      ensure
        unlock(ClIndexLockMgr::READ)
      end
    end
  end

  def all_terms(reference, wait=NO_WAIT)
    all = []
    do_read(wait) {
      @index.each do |term, refArray|
        all << term if refArray.include?(reference)
      end
    }
    all
  end

  def reference_exists?(reference, wait=NO_WAIT)
    exists = false
    do_read(wait) {
      @index.each do |term, refArray|
        if refArray.include? reference
          exists = true
          break
        end
      end
    }
    exists
  end

  def term_exists?(term, wait=NO_WAIT)
    exists = false
    do_read(wait) {
      exists = @index.keys.include?(term)
    }
    exists
  end

  def lock(lockType, wait=NO_WAIT)
    @lockMgr.lock(lockType, wait)
  end

  def unlock(lockType)
    @lockMgr.unlock(lockType)
  end
end

class ThreadSafeArray
  def initialize
    @mutex = Mutex.new
    @internalArray = []
  end

  def to_ary
    @internalArray
  end

  def method_missing(method, *args, &block)
    @mutex.synchronize do
      @internalArray.send(method, *args, &block)
    end
  end
end

class ClIndexLockMgr
  LOAD = 'load'
  SAVE = 'save'
  EDIT = 'edit'
  READ = 'read'
  WAIT = true

  def initialize
    @allowable = {
      LOAD => [],
      SAVE => [READ],
      EDIT => [],
      READ => [READ, SAVE]
    }

    @current = ThreadSafeArray.new
    @mutex = Mutex.new
  end

  def lock_approved(lockType)
    result = true
    @allowable.each_pair do |locked, allowable|
      if @current.include?(locked) && !allowable.include?(lockType)
        result = false
      end
      break if !result
    end
    result
  end

  def lock(lockType, wait=false)
    if wait
      begin
        approved = lock_approved(lockType)
      end until approved
    else
      approved = lock_approved(lockType)
    end
    @current << lockType if approved
    approved
  end

  def unlock(lockType)
    @current.delete(lockType)
  end
end

def launch_server(port='9110')
  idxServer = ClIndex.new(true)
  puts "ClIndex launching on localhost:#{port}..."
  DRb.start_service("druby://localhost:#{port}", idxServer)
  DRb.thread.join
end

if __FILE__ == $0
  if if_switch('-s')
    port = get_switch('-p')
    if port
      launch_server(port)
    else
      launch_server
    end
  end
end
