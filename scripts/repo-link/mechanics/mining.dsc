entity_spawner_command:
  type: command
  name: entity_spawner
  usage: /entity_spawner (place/spawner) <&lt>ore_name<&gt>
  description: gives you an ore spawner or places one at your cursor
  tab complete:
    - if <context.args.is_empty>:
      - determine place|spawner
    - else if <context.args.size> == 1 && "!<context.raw_args.ends_with[ ]>":
      - determine <list[place|spawner].include[<yaml[entities].list_keys[entities.ground_ores]>].filter[starts_with[<context.args.last>]]>
    - else if <context.args.size> == 1 && "<context.raw_args.ends_with[ ]>":
      - determine <yaml[entities].list_keys[entities.ground_ores]>
    - else if <context.args.size> == 2 && <list[place|spawner].contains[<context.args.first>]>:
      - determine <yaml[entities].list_keys[entities.ground_ores].filter[starts_with[<context.args.last>]]>

  script:
    - if <context.args.is_empty>:
      - inject command_syntax

    - if <context.args.size> == 1:
      - define entity_type <context.args.first>
    - else:
      - if <context.args.size> != 2:
        - inject command_syntax
      - define entity_type <context.args.get[2]>
    - inject locally validate

    - choose <context.args.first>:
      - case place:
        - inject locally place_ore

      - case spawner:
        - define entity_name "<[entity_type].replace[_].with[ ].to_titlecase>"
        - define display "<[entity_name]> Entity Spawner"
        - define lore "<list_single[<&color[#C1F2F7]>Places a(n) <[entity_name]> Entity]>"
        - define lore "<[lore].include_single[<proc[colorize].context[Left-Click:|green]> <&color[#C1F2F7]> Place Entity]>"
        - define lore "<[lore].include_single[<proc[colorize].context[Right-Click:|green]><&color[#C1F2F7]> Remove Entity]>"
        - define nbt entity_type/<[entity_type]>
        - define custom_model_data <yaml[entities].read[entities.ground_ores.<[entity_type]>.custom_model_data]>
        - give entity_spawner[display_name=<[display]>;lore=<[lore]>;nbt=<[nbt]>;custom_model_data=<[custom_model_data]>]

      - default:
        - inject locally place_ore

  validate:
    - if !<yaml[entities].list_keys[entities.ground_ores].contains[<[entity_type]>]>:
      - define reason "Invalid ore specified."
      - inject command_error

  place_ore:
    - define location <player.cursor_on||invalid>
    - if <[location]> == invalid:
      - stop
    - run spawn_ore_entity def:<[location]>|<[entity_type]>

spawn_ore_entity:
  type: task
  definitions: location|entity_type
  script:
    - create armor_stand <[location].add[0.2,1.13,0]> ore save:entity
    - flag <entry[entity].created_npc> ore.type:<[entity_type]>
    - assignment set script:mining_handler to:<entry[entity].created_npc>
    - narrate "<proc[colorize].context[Entity created:|green]> <proc[colorize].context[<&lb><[entity_type].replace[_].with[ ].to_titlecase><&rb>|yellow]>"

entity_spawner:
  type: item
  material: music_disc_11
  mechanisms:
    hides: all

ore_place:
  type: world
  events:
    on player left clicks block with:entity_spawner:
      - define location <context.location||invalid>
      - if <[location]> == invalid:
        - stop

      - determine passively cancelled
      - run spawn_ore_entity def:<[location]>|<player.item_in_hand.nbt[entity_type]>

mining_handler:
  type: assignment
  actions:
    on assignment:
      - if <npc.has_flag[ore.initiated]>:
        - stop
      - adjust <npc> gravity:false
      - adjust <npc> custom_name_visible:false
      - invisible <npc> state:true
      - flag npc ore.initiated
      - trigger name:click state:true
      - trigger name:damage state:true
      - equip <npc> helmet:leather_boots[color=85,52,38;custom_model_data=1]

    on damage:
      - run ground_ore_mining_event
    on click:
      - run ground_ore_mining_event

ground_ore_mining_event:
  type: task
  script:
    # % ██ [ Check for Developer Tool ] ██
      - wait 1t
      - if <player.item_in_hand.has_script> && <player.item_in_hand.scriptname> == entity_spawner && <npc.name> == ore:
        - narrate "<proc[colorize].context[Entity removed:|green]> <proc[colorize].context[<&lb><npc.flag[ore.type].as_element.replace[_].with[ ].to_titlecase><&rb>|yellow]>"
        - remove <npc>
        - stop

      # - ██ [ Check for cooldown ] ██
      - if <npc.has_flag[harvest_cooldown]>:
        - narrate format:colorize_red "This resource is not ready to be harvested."
        - stop

      # % ██ [ Definitions ] ██
      - define ore_type <npc.flag[ore.type]>
      - define ore_name "<[ore_type].replace[_].with[ ].to_titlecase>"
      - define ore_data <yaml[entities].read[entities.ground_ores.<[ore_type]>]>
      - define minimum_level <[ore_data].get[minimum_level]>
      - define success_chance <[ore_data].get[success_chance]>
      - define experience <[ore_data].get[experience]>
      - define respawn_time <[ore_data].get[respawn_time]>
      # $ ████████ [ ADD VALUE FOR SKILL MODIFIER ] ████████
      - define mining_level_bonus 0
      # $ ████████ [ ADD CHECK FOR CAPE ] ████████
      - if <player.flag[cape]||invalid_for_now> == sickass_mining_cape:
        - define cape_chance 5
      - else:
        - define cape_chance 0

      # % ████████ [ mining skill level check ] ████████
      - if <player.flag[gielinor.skills.mining.level]> < <[minimum_level]>:
        - narrate format:colorize_red "You must have <[minimum_level]> mining in order to harvest <[ore_name]>."
        - stop

      # % ████████ [ roll for success. ] ████████
      # $ ████████ [ ADD CHECK FOR MODIFIERS ] ████████
      - define mining_result <util.random.int[0].to[100]>
      - if <[mining_result].add[<[mining_level_bonus]>]> >= <[success_chance]>:
        - give <proc[item].context[<[ore_type]>]>
        - run add_xp def:<[experience]>|mining

        # % ████████ [ Chance for gloves/etc to not despawn. ] ████████
        # $ ████████ [ ADD SYNTAX FOR PLAYER EQUIPMENT CHECK ] ████████
        - define player_gloves <player.flag[gloves]||invalid_for_now>
        - if <list[mining_gloves|expert_mining_glove|superior_mining_gloves].contains[<[player_gloves]>]> && <[ore_data].contains[<[player_gloves]>_chance]>:
          - if <util.random.int[0].to[100]> < <yaml[entities].read[entities.ground_ores.<[ore_type]>.superior_mining_gloves_chance].sub[<[cape_chance]>]>:
            - stop

        # % ████████ [ Set cooldown, and equip models on timer. ] ████████
        - equip <npc> helmet:<npc.equipment_map.get[helmet].with[color=100,100,100]>
        - wait <[respawn_time]>s
        - equip <npc> helmet:<npc.equipment_map.get[helmet].with[color=85,52,38]>

gem_rock_ore_item:
  type: procedure
  script:
    - define chance <util.random.int[1].to[128]>
    - if <[chance]> < 5:
      - define gem diamond
    - if <[chance]> < 10:
      - define gem ruby
    - if <[chance]> < 14:
      - define gem emerald
    - if <[chance]> < 22:
      - define gem sapphire
    - if <[chance]> < 37:
      - define gem red_topaz
    - if <[chance]> < 68:
      - define gem jade
    - else:
      - define gem opal
    - determine <proc[item].context[uncut_<[gem]>]>
