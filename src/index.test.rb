# $Id: index.test.rb,v 1.14 2003/05/28 22:57:28 chrismo Exp $
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

require 'test/unit'
require 'index'

# descendant class that intentionally slows down the locking process
# to control testing
class ClIndexLockDelay < ClIndex
  def lock(lockType, wait=NO_WAIT)
    result = super(lockType, wait)
    sleep 1.0
    result
  end
end

class TestClIndex < Test::Unit::TestCase
  def set_up
    @indexfn = 'test.index.dat'
  end

  def tear_down
    File.delete(@indexfn) if File.exists?(@indexfn)
  end

  def test_index_locking
    @index = ClIndexLockDelay.new
    threads = []
    threads << Thread.new {
      Thread.current["name"] = 'add thread'
      Thread.current["actual"] = @index.add('onion', 'Page 5')
    }

    threads << Thread.new {
      sleep 0.5
      Thread.current["name"] = 'save thread'
      Thread.current["actual"] = !@index.save(@indexfn)
    }

    threads.each { |t| t.join; assert(t["actual"], t["name"]) }

    threads << Thread.new {
      Thread.current["name"] = 'add thread'
      Thread.current["actual"] = @index.add('onion', 'Page 5')
    }

    threads << Thread.new {
      sleep 0.1
      Thread.current["name"] = 'save thread'
      Thread.current["actual"] = @index.save(@indexfn, ClIndex::WAIT)
    }

    threads.each { |t| t.join; assert(t["actual"], t["name"]) }
    assert(File.exists?(@indexfn))
  end

  def test_add_remove
    @index = ClIndex.new
    term = 'onion'; ref = 'Page 5'
    @index.add(term, ref)
    hits = []
    @index.search(term, hits)
    assert_equal([[ref]], hits)
    @index.remove(ref)
    hits = []
    @index.search(term, hits)
    assert_equal([], hits)
  end

  def test_reference_exists
    @index = ClIndex.new
    term = 'onion'; ref = 'Page 5'
    @index.add(term, ref)
    assert(@index.reference_exists?(ref))
    assert(!@index.reference_exists?(ref + '6'))
  end

  def test_term_exists
    @index = ClIndex.new
    term = 'onion'; ref = 'Page 5'
    @index.add(term, ref)
    assert(@index.term_exists?(term))
    assert(!@index.term_exists?(term.reverse))
    assert(!@index.term_exists?(term + 'a'))
  end
end

class TestClIndexLockMgr < Test::Unit::TestCase
  def set_up
    @l = ClIndexLockMgr.new
  end

  def test_load_lock
    assert(@l.lock(ClIndexLockMgr::LOAD))
    assert(!@l.lock(ClIndexLockMgr::LOAD))
    assert(!@l.lock(ClIndexLockMgr::SAVE))
    assert(!@l.lock(ClIndexLockMgr::EDIT))
    assert(!@l.lock(ClIndexLockMgr::READ))
    assert(@l.unlock(ClIndexLockMgr::LOAD))
  end

  def test_save_lock
    assert(@l.lock(ClIndexLockMgr::SAVE))
    assert(!@l.lock(ClIndexLockMgr::SAVE))
    assert(!@l.lock(ClIndexLockMgr::LOAD))
    assert(!@l.lock(ClIndexLockMgr::EDIT))
    assert(@l.lock(ClIndexLockMgr::READ))
    assert(@l.unlock(ClIndexLockMgr::SAVE))
  end

  def test_edit_lock
    assert(@l.lock(ClIndexLockMgr::EDIT))
    assert(!@l.lock(ClIndexLockMgr::EDIT))
    assert(!@l.lock(ClIndexLockMgr::LOAD))
    assert(!@l.lock(ClIndexLockMgr::SAVE))
    assert(!@l.lock(ClIndexLockMgr::READ))
    assert(@l.unlock(ClIndexLockMgr::EDIT))
  end

  def test_read_lock
    assert(@l.lock(ClIndexLockMgr::READ))
    assert(@l.lock(ClIndexLockMgr::READ))
    assert(!@l.lock(ClIndexLockMgr::LOAD))
    assert(@l.lock(ClIndexLockMgr::SAVE))
    assert(!@l.lock(ClIndexLockMgr::EDIT))
    assert(@l.unlock(ClIndexLockMgr::READ))
  end

  def test_unlocking_nothing
    assert(!@l.unlock(ClIndexLockMgr::EDIT))
    assert(!@l.unlock(ClIndexLockMgr::LOAD))
    assert(!@l.unlock(ClIndexLockMgr::SAVE))
    assert(!@l.unlock(ClIndexLockMgr::READ))
  end
end

class TestClIndexLockMgrWaiting < Test::Unit::TestCase
  def set_up
    @l = ClIndexLockMgr.new
  end

  def test_wait
    # this currently does not test every combination like
    # the TestClIndexLockMgr.test_*_lock methods do. This test assumes that
    # if those tests pass, then the combinations are all setup correctly.
    # This test just picks one of the combinations to make sure the
    # ::WAIT option works as well.

    threads = []
    threads << Thread.new {
      Thread.current["name"] = 'lock thread'
      Thread.current["actual"] = @l.lock(ClIndexLockMgr::LOAD)
      sleep 1.0
      @l.unlock(ClIndexLockMgr::LOAD)
    }

    threads << Thread.new {
      sleep 0.3
      Thread.current["name"] = 'edit thread - no wait'
      Thread.current["actual"] = !@l.lock(ClIndexLockMgr::EDIT)
    }

    threads << Thread.new {
      sleep 0.3
      Thread.current["name"] = 'edit thread - wait'
      Thread.current["actual"] = @l.lock(ClIndexLockMgr::EDIT, ClIndexLockMgr::WAIT)
    }

    threads.each { |t| t.join; assert(t["actual"], t["name"]) }
  end
end

class TestClIndexMultiUser < Test::Unit::TestCase
  def set_up
    @index = ClIndexLockDelay.new
    @index.add('pickle', 'Page 6')
    @index.add('cheese', 'Page 7')
    @index.save
  end

  def do_test_two_client(clientAAction, clientBAction, clientBWait, clientBExpectedResult)
    puts "testing #{clientAAction.inspect}, #{clientBAction.inspect}, wait=#{clientBWait}, expect=#{clientBExpectedResult}"
    ahits, bhits = [], []
    threads = []
    threads << Thread.new {
      Thread.current["name"] = 'clientA'
      case clientAAction
      when ClIndexLockMgr::LOAD then Thread.current["actual"] = @index.load
      when ClIndexLockMgr::SAVE then Thread.current["actual"] = @index.save
      when ClIndexLockMgr::READ then Thread.current["actual"] = @index.search('onion', ahits)
      when ClIndexLockMgr::EDIT then Thread.current["actual"] = @index.add('onion', 'Page 5')
      end
    }

    threads << Thread.new {
      sleep 0.5
      Thread.current["name"] = 'clientB'
      case clientBAction
      when ClIndexLockMgr::LOAD then Thread.current["actual"] = @index.load('index.dat', clientBWait)
      when ClIndexLockMgr::SAVE then Thread.current["actual"] = @index.save('index.dat', clientBWait)
      when ClIndexLockMgr::READ then Thread.current["actual"] = @index.search('onion', bhits, clientBWait)
      when ClIndexLockMgr::EDIT then Thread.current["actual"] = @index.add('onion', 'Page 5', clientBWait)
      end
    }

    threads.each { |t|
      t.join
      if t["name"] == 'clientA'
        expected = true
      elsif t["name"] == 'clientB'
        expected = clientBExpectedResult
      end
      assert_equal(expected, t["actual"], t["name"])
    }
  end

  def test_two_clients
    puts
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::LOAD, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::LOAD, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::SAVE, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::SAVE, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::EDIT, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::EDIT, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::READ, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::LOAD, ClIndexLockMgr::READ, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::LOAD, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::LOAD, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::SAVE, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::SAVE, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::EDIT, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::EDIT, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::READ, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::SAVE, ClIndexLockMgr::READ, ClIndex::NO_WAIT, true )
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::LOAD, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::LOAD, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::SAVE, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::SAVE, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::EDIT, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::EDIT, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::READ, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::EDIT, ClIndexLockMgr::READ, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::LOAD, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::LOAD, ClIndex::NO_WAIT, false)
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::SAVE, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::SAVE, ClIndex::NO_WAIT, true )
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::EDIT, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::EDIT, ClIndex::NO_WAIT, false) # if true (1) will it crash program? (2) will it give acceptable results?
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::READ, ClIndex::WAIT   , true )
    do_test_two_client(ClIndexLockMgr::READ, ClIndexLockMgr::READ, ClIndex::NO_WAIT, true )
  end
end

class TestThreadSafeArray < Test::Unit::TestCase
  def test_ts_array_simple
    @a = ThreadSafeArray.new
    @a << 1
    assert_equal([1], @a.to_ary)
    @a.delete(1)
    assert_equal([], @a.to_ary)
  end

  def test_ts_array
    # if @a is a plain Array, then the each call will be interrupted by
    # the 2nd thread setting [0,0]. ThreadSafeArray ensures the each
    # block finishes before the 2nd thread can do its insertion.
    # Thx to Guy Decoux for the test case http://ruby-talk.com/40317
    @a = ThreadSafeArray.new
    @a << [1, 2, 3]
    @a.flatten!
    @b = []
    t = Thread.new do
       @a.each do |x|
          @b << x
          Thread.pass
       end
    end
    Thread.new do
       sleep 0.1 # to help ensure this thread goes 2nd
       @a[0,0] = [12, 24]
    end
    t.join
    assert_equal([1,2,3], @b)
  end

  def test_equality

  end
end
