Parallel Actor Framework

core concepts:

- Stage - main container for actors & all associated methods/data
- Post_Office - embedded by Stage, contains subscriptions & messages
- Actor - base type for your actors

internally uses core's handle_map to map handles to Actors.

basic usage:

```odin
My_Actor :: struct {
  using actor: Actor,
  init: proc(^My_Actor),
  tick: proc(^My_Actor),
  kill: proc(^My_Actor),
}

My_Event :: struct{}

my_event_handler :: proc(a: ^My_Actor, e: ^My_Event) {}

stage := make_stage("optional name")
defer delete_stage(&stage)

a := spawn(&stage, My_Actor{my_init, my_tick, my_kill}, "optional name")
defer kill(&stage, a)
subscribe(&stage, a, my_event_handler)
defer unsubscribe(&stage, a, My_Event)

for running do tick(&stage)

send(&stage, a, My_Event{})
publish(&stage, My_Event{})

it := make_iterator(&stage)
for actor, handle in iterate(&it) {}
for my_actor, handle in iterate(&it, My_Actor) {}
```



