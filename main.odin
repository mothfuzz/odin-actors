package actors

import "core:fmt"


main_scene: Stage
counter: int

TestActor :: struct {
    using actor: Actor,
    init: proc(^TestActor),
    tick: proc(^TestActor),
    kill: proc(^TestActor),
    i: i32,
    f: f32,
}

MyEvent :: struct {
    f: f32,
}

my_event_handler :: proc(a: ^TestActor, e: ^MyEvent) {
    fmt.println("actor", a.handle, "got a float:", e.f)
}


test_tick :: proc(a: ^TestActor) {
    if counter == 10 {
        //handled on tick 11
        kill(&main_scene, a)
        return
    }
    if counter == 5 {
        //handled on tick 6
        send(&main_scene, a, MyEvent{3.14})
    }
}

test_init :: proc(a: ^TestActor) {
    fmt.println("hi! my name is", a.name, "and I belong to", main_scene.name)
    subscribe(&main_scene, a, my_event_handler)
}

test_kill :: proc(a: ^TestActor) {
    fmt.println("I was killed!!")
}

import "core:mem"
main :: proc() {
    when ODIN_OS != .JS {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    {
        main_scene = make_stage("Eve")
        defer delete_stage(&main_scene)

        for i := 0; i < 16; i += 1 {
            a := spawn(&main_scene, TestActor{i=i32(i), f=f32(i*i), init=test_init, tick=test_tick, kill=test_kill}, "Joe")
            fmt.println(a)
        }

        it := make_iterator(&main_scene)
        for ta, _ in iterate(&it, TestActor) {
            fmt.println(ta.i, ta.f)
        }

        for i in 0..=10 {
            counter += 1
            fmt.println("tick:", counter)
            tick(&main_scene)
        }
    }


    when ODIN_OS != .JS {
        if len(track.allocation_map) > 0 {
            fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
            for _, entry in track.allocation_map {
                fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
            }
        }
        if len(track.bad_free_array) > 0 {
            fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
            for entry in track.bad_free_array {
                fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
            }
        }
        mem.tracking_allocator_destroy(&track)
    }
}
