package actors

import hm "core:container/handle_map"
import "base:intrinsics"
import "core:reflect"

Handle :: struct {
    idx: u32,
    gen: u32,
}

State :: enum {
    Spawned,
    Active,
    Killed,
}

Actor :: struct {
    using handle: Handle,
    state: State,
    handle_index: int,
    user_init: proc(^Actor),
    user_tick: proc(^Actor),
    user_kill: proc(^Actor),
    free_proc: proc(^Actor),
    name: string,
    type: typeid,
}

Actor_Ptr :: struct {
    handle: Handle,
    ptr: ^Actor,
}

Stage :: struct {
    actors: hm.Dynamic_Handle_Map(Actor_Ptr, Handle),
    spawns: [dynamic]Handle,
    kills: [dynamic]Handle,
    using stage_sync: Stage_Sync,
    handles: [dynamic]Handle,
    name: string,

    using post_office: Post_Office,
}

make_stage :: proc(name: string = "") -> (stage: Stage) {
    stage.name = name
    hm.dynamic_init(&stage.actors, context.allocator)
    return
}

delete_stage :: proc(s: ^Stage) {
    delete_threads(s)
    delete_post_office(s)
    delete(s.handles)
    it := hm.iterator_make(&s.actors)
    for actor, handle in hm.iterate(&it) {
        hm.remove(&s.actors, handle)
        actor.ptr->free_proc()
    }
    hm.dynamic_destroy(&s.actors)
    delete(s.spawns)
    delete(s.kills)
}

count :: proc(s: ^Stage) -> uint {
    return hm.len(s.actors)
}

@(private)
actor_offset :: proc($T: typeid) -> uintptr
where intrinsics.type_is_subtype_of(T, Actor) {
    @(static) offset: uintptr
    @(static) init: bool = false
    if !init {
        for i in 0..<intrinsics.type_struct_field_count(T) {
            field := reflect.struct_field_at(T, i)
            if field.type.id == Actor && field.is_using {
                offset = field.offset
                init = true
                break   
            }
        }
    }
    return offset
}

@(private)
free_proc :: proc($T: typeid) -> proc(^Actor) {
    @(static) free_proc: proc(^Actor)
    @(static) init: bool = false
    if !init {
        free_proc = proc(actor: ^Actor) {
            ptr := cast(^T)(uintptr(actor) - actor_offset(T))
            free(ptr)
        }
        init = true
    }
    return free_proc
}

@(private)
construct_actor :: proc(t: $T, name: string) -> Actor_Ptr
where intrinsics.type_is_subtype_of(T, Actor) {
    actor := new(T)
    actor^ = t
    when intrinsics.type_has_field(T, "init") {
        actor.user_init = proc(a: ^Actor) {
            self := cast(^T)(uintptr(a) - actor_offset(T))
            self->init()
        }
    }
    when intrinsics.type_has_field(T, "tick") {
        actor.user_tick = proc(a: ^Actor) {
            self := cast(^T)(uintptr(a) - actor_offset(T))
            self->tick()
        }
    }
    when intrinsics.type_has_field(T, "kill") {
        actor.user_kill = proc(a: ^Actor) {
            self := cast(^T)(uintptr(a) - actor_offset(T))
            self->kill()
        }
    }
    actor.free_proc = free_proc(T)
    actor.name = name
    actor.type = T
    actor.state = .Spawned
    return {ptr=actor}
}

tick :: proc(s: ^Stage) {

    init_threads(s)

    for handle in s.spawns {
        if a, ok := hm.get(&s.actors, handle); ok {
            a := a.ptr
            if a.user_init != nil {
                a->user_init()
            }
            a.state = .Active
            a.handle_index = len(s.handles)
            append(&s.handles, handle)
        }
    }
    clear(&s.spawns)
    for handle in s.kills {
        if a, ok := hm.get(&s.actors, handle); ok {
            a := a.ptr
            if a.user_kill != nil {
                a->user_kill()
            }

            last := len(s.handles) - 1
            if a.handle_index != last {
                if other, ok := hm.get(&s.actors, s.handles[last]); ok {
                    other.ptr.handle_index = a.handle_index
                }
            }
            unordered_remove(&s.handles, a.handle_index)
            
            unsubscribe_all(s, handle)
            hm.remove(&s.actors, handle)
            a->free_proc()
        }
    }
    clear(&s.kills)

    process_subscriptions(s)

    process_threads(s)
}

Iterator :: hm.Dynamic_Handle_Map_Iterator(hm.Dynamic_Handle_Map(Actor_Ptr, Handle))
make_iterator :: proc(s: ^Stage) -> Iterator {
    return hm.iterator_make(&s.actors)
}
iterate_untyped :: proc(it: ^Iterator) -> (^Actor, Handle, bool) {
    a, handle, ok := hm.iterate(it)
    return a.ptr, handle, ok
}

iterate_typed :: proc(it: ^Iterator, $T: typeid) -> (^T, Handle, bool) {
    a, handle, ok := hm.iterate(it)
    if ok {
        if a.ptr.type == T {
            return cast(^T)(a.ptr), handle, ok
        } else {
            return iterate_typed(it, T)
        }
    } else {
        return nil, {}, false
    }
}

iterate :: proc{iterate_untyped, iterate_typed}
