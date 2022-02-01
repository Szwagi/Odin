package container_lru

import "core:intrinsics"
import "core:mem"
_ :: intrinsics
_ :: mem

Node :: struct($Key, $Value: typeid) where intrinsics.type_is_valid_map_key(Key) {
	prev, next: ^Node(Key, Value),
	key:   Key,
	value: Value,
}

// Cache is an LRU cache. It automatically removes entries as new entries are
// added if the capacity is reached. Entries are removed based on how recently
// they were used where the oldest entries are removed first.
Cache :: struct($Key, $Value: typeid) where intrinsics.type_is_valid_map_key(Key) {
	head: ^Node(Key, Value),
	tail: ^Node(Key, Value),

	entries: map[Key]^Node(Key, Value),

	count:    int,
	capacity: int,

	node_allocator: mem.Allocator,

	on_remove: proc(key: Key, value: Value, user_data: rawptr),
	on_remove_user_data: rawptr,
	call_on_remove_on_destroy: bool,
}

// init initializes a Cache
init :: proc(c: ^$C/Cache($Key, $Value), capacity: int, entries_allocator := context.allocator, node_allocator := context.allocator) {
	c.entries.allocator = entries_allocator
	c.node_allocator = node_allocator
	c.capacity = capacity
}

// destroy deinitializes a Cache
destroy :: proc(c: ^$C/Cache($Key, $Value)) {
	for _, node in c.entries {
		if c.call_on_remove_on_destroy && c.on_remove != nil {
			c.on_remove(node.key, node.value, c.on_remove_user_data)
		}
		free(node, c.node_allocator)
	}
	clear(&c.entries)
	delete(c.entries)
	c.head = nil
	c.tail = nil
	c.count = 0
}

// set the given key value pair. This operation updates the recent usage of the item.
set :: proc(c: ^$C/Cache($Key, $Value), key: Key, value: Value) -> mem.Allocator_Error {
	if e, ok := c.entries[key]; ok {
		e.value = value
		return nil
	}

	e := new(Node(Key, Value), c.node_allocator) or_return
	e.key = key
	e.value = value

	_push_front_node(c, e)
	if c.count > c.capacity {
		_remove_node(c, c.tail)
	}

	c.entries[key] = e
	return nil
}

// get a value from the cache from a given key. This operation updates the usage of the item.
get :: proc(c: ^$C/Cache($Key, $Value), key: Key) -> (value: Value, ok: bool) #optional_ok {
	e: ^Node(Key, Value)
	e, ok = c.entries[key]
	if !ok {
		return
	}
	_pop_node(c, e)
	_push_front_node(c, e)
	return e.value, true
}

// get_ptr gets the pointer to a value the cache from a given key. This operation updates the usage of the item.
get_ptr :: proc(c: ^$C/Cache($Key, $Value), key: Key) -> (value: ^Value, ok: bool) #optional_ok {
	e: ^Node(Key, Value)
	e, ok = c.entries[key]
	if !ok {
		return
	}
	_pop_node(c, e)
	_push_front_node(c, e)
	return &e.value, true
}

// peek gets the value from the cache from a given key without updating the recent usage.
peek :: proc(c: ^$C/Cache($Key, $Value), key: Key) -> (value: Value, ok: bool) #optional_ok {
	e: ^Node(Key, Value)
	e, ok = c.entries[key]
	if !ok {
		return
	}
	return e.value, true
}

// exists checks for the existence of a value from a given key without updating the recent usage.
exists :: proc(c: ^$C/Cache($Key, $Value), key: Key) -> bool {
	return key in c.entries
}

// remove removes an item from the cache.
remove :: proc(c: ^$C/Cache($Key, $Value), key: Key) -> bool {
	e, ok := c.entries[key]
	if !ok {
		return false
	}
	_remove_node(c, e)
	return true
}


@(private)
_remove_node :: proc(c: ^$C/Cache($Key, $Value), node: ^Node(Key, Value)) {
	if c.head == node {
		c.head = node.next
	}
	if c.tail == node {
		c.tail = node.prev
	}
	if node.prev != nil {
		node.prev.next = node.next
	}
	if node.next != nil {
		node.next.prev = node.prev
	}
	node.prev = nil
	node.next = nil

	c.count -= 1

	delete_key(&c.entries, node.key)

	if c.on_remove != nil {
		c.on_remove(node.key, node.value, c.on_remove_user_data)
	}

	free(node, c.node_allocator)

}

@(private)
_push_front_node :: proc(c: ^$C/Cache($Key, $Value), e: ^Node(Key, Value)) {
	if c.head != nil {
		e.next = c.head
		e.next.prev = e
	}
	c.head = e
	if c.tail == nil {
		c.tail = e
	}
	e.prev = nil

	c.count += 1
}

@(private)
_pop_node :: proc(c: ^$C/Cache($Key, $Value), e: ^Node(Key, Value)) {
	if e == nil {
		return
	}
	if e.prev != nil {
		e.prev.next = e.next
	}

	if e.next != nil {
		e.next.prev = e.prev
	}
	e.prev = nil
	e.next = nil
}