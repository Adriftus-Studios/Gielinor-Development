entity_spawner_command:
  type: command
  name: entity_spawner
  usage: /entity_spawner (place/spawner) <&lt>ore_name<&gt>
  description: gives you an ore spawner or places one at your cursor
  tab complete:
    - if <context.args.is_empty>:
      - determine place|spawner
    - else if <context.args.size> == 1 && "!<context.raw_args.ends_with[ ]>":
      - determine <list[place|spawner].include[<script[gielinor_mining_handler].list_keys[ore_handling_data]>].filter[starts_with[<context.args.last>]]>
    - else if <context.args.size> == 1 && "<context.raw_args.ends_with[ ]>":
      - determine <script[gielinor_mining_handler].list_keys[ore_handling_data]>
    - else if <context.args.size> == 2 && <list[place|spawner].contains[<context.args.first>]>:
      - determine <script[gielinor_mining_handler].list_keys[ore_handling_data].filter[starts_with[<context.args.last>]]>

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
        - define lore "<[lore].include_single[<proc[colorize].context[Left-Click:|green]> <&color[#C1F2F7]> Place]>"
        - define lore "<[lore].include_single[<proc[colorize].context[Right-Click:|green]><&color[#C1F2F7]> Remove]>"
        - define nbt entity_type/<[entity_type]>
        - define custom_model_data <script[gielinor_mining_handler].data_key[ore_handling_data.<[entity_type]>.custom_model_data]>
        - give entity_spawner[display_name=<[display]>;lore=<[lore]>;nbt=<[nbt]>;custom_model_data=<[custom_model_data]>]

      - default:
        - inject locally place_ore

  validate:
    - if !<script[gielinor_mining_handler].list_keys[ore_handling_data].contains[<[entity_type]>]>:
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
    - assignment set script:gielinor_mining_handler to:<entry[entity].created_npc>
    - narrate "<proc[colorize].context[Entity created:|green]> <proc[colorize].context[<&lb><[entity_type].replace[_].with[ ].to_titlecase><&rb>|yellow]>"

entity_spawner:
  type: item
  material: music_disc_11
  mechanisms:
    hides: all

ore_place:
  type: world
  debug: true
  events:
    on player left clicks block with:entity_spawner:
      - define location <context.location||invalid>
      - if <[location]> == invalid:
        - stop

      - determine passively cancelled
      - run spawn_ore_entity def:<[location]>|<player.item_in_hand.nbt[entity_type]>

      - create armor_stand <[location].add[0.2,1.13,0]> ore save:entity
      - flag <entry[entity].created_npc> ore.type:<[entity_type]>
      - assignment set script:gielinor_mining_handler to:<entry[entity].created_npc>
      - narrate "<proc[colorize].context[Entity created:|green]> <proc[colorize].context[<&lb><[entity_type].replace[_].with[ ].to_titlecase><&rb>|yellow]>"

gielinor_mining_handler:
  type: assignment
  debug: true
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

    on click:
      - wait 1t
      - ratelimit <player> 1t
      - if <player.item_in_hand.has_script> && <player.item_in_hand.scriptname> == entity_spawner:
        - if <npc.name> == ore:
          - narrate "<proc[colorize].context[Entity removed:|green]> <proc[colorize].context[<&lb><npc.flag[ore.type].as_element.replace[_].with[ ].to_titlecase><&rb>|yellow]>"
          - remove <npc>
          - stop
      # - ████████ [ Check for cooldown ] ████████
      - if <npc.has_flag[harvest_cooldown]>:
        - narrate format:colorize_red "This resource is not ready to be harvested."
        - stop

      # % ████████ [ Definitions ] ████████
      - define ore_node_type  <npc.flag[type]>
      - define ore_type <npc.flag[type]||iron>_ore
      - define ore_name <script.data_key[ore_handling_data.<[ore_type]>.display_name]>
      - define minimum_level <script.data_key[ore_handling_data.<[ore_type]>.minimum_level]>
      - define success_chance <script.data_key[ore_handling_data.<[ore_type]>.success_chance]>
      - define exp_amount <script.data_key[ore_handling_data.<[ore_type]>.exp_amount]>
      - define respawn_time <script.data_key[ore_handling_data.<[ore_type]>.respawn_time]>
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
        - run add_xp def:<[exp_amount]>|mining
        # % ████████ [ Chance for gloves/etc to not despawn. ] ████████
        # $ ████████ [ ADD SYNTAX FOR PLAYER EQUIPMENT CHECK ] ████████
        - if <player.flag[gloves]||invalid_for_now> == mining_gloves && <script.data_key[ore_handling_data.<[ore_type]>.mining_gloves_chance]> > 0:
          - define chance <util.random.int[0].to[100]>
          - if <[chance]> < <script.data_key[ore_handling_data.<[ore_type]>.mining_gloves_chance].sub[<[cape_chance]>]>:
            - stop
        - if <player.flag[gloves]||invalid_for_now> == expert_mining_gloves && <script.data_key[ore_handling_data.<[ore_type]>.expert_mining_gloves_chance]> > 0:
          - define chance <util.random.int[0].to[100]>
          - if <[chance]> < <script.data_key[ore_handling_data.<[ore_type]>.expert_mining_gloves_chance].sub[<[cape_chance]>]>:
            - stop
        - if <player.flag[gloves]||invalid_for_now> == superior_mining_gloves && <script.data_key[ore_handling_data.<[ore_type]>.superior_mining_gloves_chance]> > 0:
          - define chance <util.random.int[0].to[100]>
          - if <[chance]> < <script.data_key[ore_handling_data.<[ore_type]>.superior_mining_gloves_chance].sub[<[cape_chance]>]>:
            - stop
        # % ████████ [ Set cooldown, and equip models on timer. ] ████████
        - if <[respawn_time]> > 0:
          - flag <npc> harvest_cooldown d:<[respawn_time]>s
          - inventory adjust d:<npc.inventory> slot:40 color:100,100,100
          - wait <[respawn_time]>s
          - inventory adjust d:<npc.inventory> slot:40 color:85,52,38


  ore_handling_data:
#-    template_ore:
#-        minimum_level:
#-        success_chance:
#-        exp_amount:
#-        respawn_time:
#-        mining_gloves_chance:
#-        superior_mining_gloves_chance:
#-        expert_mining_gloves_chance:
#-        display_name:
    chocolate_ore:
        minimum_level: 0
        success_chance: 50
        exp_amount: 0
        respawn_time: 0
        display_name: Chocolate
    copper_ore:
        custom_model_data: 4
        minimum_level: 1
        success_chance: 50
        exp_amount: 17.5
        respawn_time: 2.4
        display_name: "Copper Ore"
    rock_ore:
        minimum_level: 1
        success_chance: 50
        exp_amount: 1
        respawn_time: 5.4|11.4|23.4
        display_name: "Elemental Rocks"
    tin_ore:
        custom_model_data: 14
        minimum_level: 1
        success_chance: 50
        exp_amount: 17.5
        respawn_time: 2.4
        display_name: "Tin Ore"
        color: 0,0,0
    clay_ore:
        minimum_level: 1
        success_chance: 50
        exp_amount: 5
        respawn_time: 1.2
        display_name: Clay
    rune_essence_ore:
        minimum_level: 1
        success_chance: 50
        exp_amount: 5
        respawn_time: 0
        display_name: "Rune Essence"
    limestone_ore:
        minimum_level: 10
        success_chance: 50
        exp_amount: 26.5
        respawn_time: 5.4
        display_name: Limestone
    blurite_ore:
        custom_model_data: 2
        minimum_level: 10
        success_chance: 50
        exp_amount: 17.5
        respawn_time: 25
        display_name: "Blurite Ore"
        color: 0,0,0
    iron_ore:
        custom_model_data: 8
        minimum_level: 15
        success_chance: 50
        exp_amount: 35
        respawn_time: 5.4
        display_name: "Iron Ore"
        color: 160,101,64
    daeyalt_ore:
        custom_model_data: 5
        minimum_level: 20
        success_chance: 50
        exp_amount: 17.5
        respawn_time: 28
        display_name: "Daeyalt Ore"
        color: 0,0,0
    silver_ore:
        custom_model_data: 13
        minimum_level: 20
        success_chance: 50
        exp_amount: 40
        respawn_time: 60
        mining_gloves_chance: 50
        expert_mining_gloves_chance: 50
        display_name: "Silver Ore"
        color: 0,0,0
    ash_ore:
        minimum_level: 22
        success_chance: 50
        exp_amount: 10
        respawn_time: 30
        display_name: Ash
    coal_ore:
        custom_model_data: 3
        minimum_level: 30
        success_chance: 50
        exp_amount: 50
        respawn_time: 30
        mining_gloves_chance: 40
        expert_mining_gloves_chance: 40
        display_name: "Coal Ore"
        color: 0,0,0
    pay-dirt_ore:
        minimum_level: 30
        success_chance: 50
        exp_amount: 60
        respawn_time: 60
        display_name: Pay-Dirt
    sandstone_ore:
        minimum_level: 35
        success_chance: 50
        exp_amount: 30|40|50|60
        respawn_time: 5
        display_name: Sandstone
    gold_ore:
        custom_model_data: 7
        minimum_level: 40
        success_chance: 50
        exp_amount: 65
        respawn_time: 60
        mining_gloves_chance: 33
        expert_mining_gloves_chance: 34
        display_name: "Gold Ore"
        color: 0,0,0
    gem_ore:
        minimum_level: 40
        success_chance: 50
        exp_amount: 65
        respawn_time: 59.4
        display_name: Gems
    sulphur_ore:
        minimum_level: 42
        success_chance: 50
        exp_amount: 25
        respawn_time: 25.2
        display_name: Sulphur
    granite_ore:
        minimum_level: 45
        success_chance: 50
        exp_amount: 50|60|75
        respawn_time: 5
        display_name: Granite
    mithril_ore:
        custom_model_data: 11
        minimum_level: 55
        success_chance: 50
        exp_amount: 80
        respawn_time: 12025
        expert_mining_gloves_chance: 25
        display_name: "Mithril Ore"
        color: 0,0,0
    lunar_ore:
        custom_model_data: 10
        minimum_level: 60
        success_chance: 50
        exp_amount: 0
        respawn_time: 0
        display_name: "Lunar Ore"
        color: 0,0,0
    daeyalt_shard_ore:
        minimum_level: 60
        success_chance: 50
        exp_amount: 5
        respawn_time: 60
        display_name: "Daeyalt shards"
    lovakite_ore:
        custom_model_data: 9
        minimum_level: 65
        success_chance: 50
        exp_amount: 10
        respawn_time: 35
        display_name: "Lovakite Ore"
        color: 0,0,0
    adamantite_ore:
        custom_model_data: 1
        minimum_level: 70
        success_chance: 50
        exp_amount: 95
        respawn_time: 240
        mining_gloves_chance: 16
        expert_mining_gloves_chance: 17
        display_name: "Adamantite Ore"
        color: 0,0,0
    soft_clay_ore:
        minimum_level: 70
        success_chance: 50
        exp_amount: 5
        respawn_time: 1.2
    #@  mining_gloves_chance: 50
        display_name: "Soft Clay"
    runite_ore:
        custom_model_data: 12
        minimum_level: 85
        success_chance: 50
        exp_amount: 125
        respawn_time: 720|360
        mining_gloves_chance: 12
        expert_mining_gloves_chance: 13
        display_name: "Runite Ore"
        color: 0,0,0
    amethyst_ore:
        minimum_level: 92
        success_chance: 50
        exp_amount: 240
        respawn_time: 75
        expert_mining_gloves_chance: 25
        display_name: "Amethyst Ore"

firework_show:
  type: command
  name: firework_show
  description: Launches a firework show.
  usage: /firework_show
  permission: adriftus.admin
  script:
    - define locations <player.location.find.surface_blocks.within[15].parse[above]>
    - define colors <list[red|blue|green|yellow|purple|orange]>
    - repeat 120:
      - choose <util.random.int[1].to[4]>:
        - case 1:
          - firework <[locations].random> power:<util.random.decimal[1].to[3]> random primary:<[colors].random> fade:<[colors].random>
        - case 2:
          - firework <[locations].random> power:<util.random.decimal[1].to[3]> random primary:<[colors].random> fade:<[colors].random> trail
        - case 3:
          - firework <[locations].random> power:<util.random.decimal[1].to[3]> random primary:<[colors].random> fade:<[colors].random> flicker trail
        - case 4:
          - firework <[locations].random> power:<util.random.decimal[1].to[3]> random primary:<[colors].random> fade:<[colors].random> flicker
      - wait 1s
