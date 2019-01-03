clIndex
=======

clIndex is a generic index DRb server. The core index is a hash, each key is an
individual term, each value is an array of references for that term. It searches
the index with a simple regexp grep against the hash keys to return a single
array of all references on matching terms. Multi-user ready via a simple locking
mechanism that probably doesn't scale too well.

BSD License.