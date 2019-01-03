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
          Marshal.dump(@index, f)
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
        File.open(filename) do |f|
          @index = Marshal.load(f)
        end
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
