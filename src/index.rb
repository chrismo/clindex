# frozen_string_literal: true

require 'drb'
require 'rubygems'
gem 'clutil'
require 'cl/util/console'

# TODO: create a batch_add method? This would allow a whole page full of terms
# to be queued and the index locked for the duration to prevent a concurrent
# query from getting a partial result
class ClIndex
  attr_accessor :index

  WAIT = true
  NO_WAIT = false

  def initialize(verbose_server = false)
    @index = {}
    @lock_mgr = ClIndexLockMgr.new
    @verbose_server = verbose_server
  end

  def assign(src)
    @index = src.index
  end

  # refactor with do_read?
  def do_edit(wait)
    locked = lock(ClIndexLockMgr::EDIT, wait)
    return unless locked

    begin
      yield if block_given?
    ensure
      unlock(ClIndexLockMgr::EDIT)
    end
  end

  def add(term, reference, wait = NO_WAIT)
    success = false
    do_edit(wait) {
      @index[term] = [] if @index[term].nil?
      @index[term] << reference
      @index[term].uniq!
      success = true
    }
    success
  end

  def remove(reference, wait = NO_WAIT)
    success = false
    do_edit(wait) {
      @index.each_pair do |term, ref_array|
        @index[term].delete(reference) if ref_array.include?(reference)
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
  def save(filename = 'index.dat', wait = NO_WAIT)
    locked = lock(ClIndexLockMgr::SAVE, wait)
    if locked
      begin
        File.open(filename, File::CREAT | File::TRUNC | File::RDWR) do |f|
          Marshal.dump(@index, f)
        end
      ensure
        unlock(ClIndexLockMgr::SAVE)
      end
    end
    locked
  end

  def load(filename = 'index.dat', wait = NO_WAIT)
    locked = lock(ClIndexLockMgr::LOAD, wait)
    if locked
      begin
        File.open(filename) do |f|
          @index = Marshal.load(f)
        end
      ensure
        unlock(ClIndexLockMgr::LOAD)
      end
    end
    locked
  end

  def search(term, hits, wait = NO_WAIT)
    puts 'searching...' if @verbose_server
    success = false
    do_read(wait) {
      success = true
      terms = @index.keys.grep(/#{term}/i)
      terms.each do |this_term|
        hits << @index[this_term]
      end
      hits = hits.flatten.uniq.sort
    }
    success
  end

  def do_read(wait)
    locked = lock(ClIndexLockMgr::READ, wait)
    return unless locked

    begin
      yield if block_given?
    ensure
      unlock(ClIndexLockMgr::READ)
    end
  end

  def all_terms(reference, wait = NO_WAIT)
    all = []
    do_read(wait) {
      @index.each do |term, ref_array|
        all << term if ref_array.include?(reference)
      end
    }
    all
  end

  def reference_exists?(reference, wait = NO_WAIT)
    exists = false
    do_read(wait) {
      @index.each do |_, ref_array|
        if ref_array.include? reference
          exists = true
          break
        end
      end
    }
    exists
  end

  def term_exists?(term, wait = NO_WAIT)
    exists = false
    do_read(wait) {
      exists = @index.key?(term)
    }
    exists
  end

  def lock(lock_type, wait = NO_WAIT)
    @lock_mgr.lock(lock_type, wait)
  end

  def unlock(lock_type)
    @lock_mgr.unlock(lock_type)
  end
end

class ThreadSafeArray
  def initialize
    @mutex = Mutex.new
    @internal_array = []
  end

  def to_ary
    @internal_array
  end

  def method_missing(method, *args, &block)
    @mutex.synchronize do
      @internal_array.send(method, *args, &block)
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

  def lock_approved(lock_type)
    result = true
    @allowable.each_pair do |locked, allowable|
      if @current.include?(locked) && !allowable.include?(lock_type)
        result = false
      end
      break unless result
    end
    result
  end

  def lock(lock_type, wait = false)
    approved = nil
    if wait
      loop do
        approved = lock_approved(lock_type)
        break if approved
      end
    else
      approved = lock_approved(lock_type)
    end
    @current << lock_type if approved
    approved
  end

  def unlock(lock_type)
    @current.delete(lock_type)
  end
end

def launch_server(port = '9110')
  idx_server = ClIndex.new(true)
  puts "ClIndex launching on localhost:#{port}..."
  DRb.start_service("druby://localhost:#{port}", idx_server)
  DRb.thread.join
end

if $0 == __FILE__
  if if_switch('-s')
    port = get_switch('-p')
    if port
      launch_server(port)
    else
      launch_server
    end
  end
end
