# Emberfield

按照 [spec](spec) 实现的 Godot 4 / GDScript 装备驱动 2D ARPG MVP。无需插件、外部素材或网络连接。

## 运行

用 Godot 4.3+ 导入当前目录的 `project.godot`，按 **F5** 运行主场景。已在 macOS Godot **4.6.3** 进行无界面验证。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## 操作

| 输入 | 行为 |
| --- | --- |
| WASD / 方向键 | 移动 |
| 鼠标 | 瞄准 |
| 按住左键 / Q | Weapon 主动技能 |
| 按住右键 / E | Offhand 主动技能 |
| F | 拾取附近装备 |
| I / Tab | 打开或关闭装备背包，暂停战斗 |
| 点击背包装备 | 装备并替换当前槽位 |
| 点击已穿装备 | 卸下，立即失去技能和属性 |
| 悬停装备 | 查看品质、属性和当前装备对比 |
| H / Esc | 帮助 / 暂停；Esc 也可关闭背包 |
| R | 胜利后进入下一轮，失败后重试 |

打开装备界面后，左侧人物面板显示当前/最大生命、装备攻击加成、总攻速、总移速、伤害倍率、两个主动技能的最终单次伤害与攻击频率/CD，以及被动效果。换装或卸装立即更新；悬停属性数值可查看来源和计算说明。

完成三波战斗并击败 Warden 即通关。Boss 的橙色圆圈会在一秒后造成伤害。击杀恢复 4 HP；通关和失败时回收所有地面装备，保留装备继续挑战。新一轮怪物强度增加 25%，掉落装备等级随轮次增长。每次启动游戏都从第一轮、140 基础生命、四个空装备槽和空背包开始，不读写存档。旧版本的存档不会被载入，无需手动删除。同一次运行内，通关继续或失败重试仍保留装备。

## Build 与装备

四个槽位均由装备提供技能：Weapon / Offhand 主动，Helmet / Necklace 被动。出生点放置 Iron Blade 和 Ember Orb，按 F 拾取、I 打开背包并手动装备；装备第一个主动技能后才开始刷怪。其余装备通过掉落获得。两个主动槽位对等，支持双 Basic、Basic + Power、双 Power；双 Power 同时冷却时无法攻击。

- **Cleave + Frost Nova**：近身扫击清群，冰环减速争取走位空间。
- **Fireball + Frost Nova**：远程爆炸加冰环控场，在两次爆发间走位。
- **Slash**：高频单体近战；**Cleave**：较低单体伤害，命中前方所有目标。
- **Toughness**：增加 65 最大 HP；重复装备不叠加同名被动。
- **Bloodlust**：击杀后 4 秒内伤害提升 40%，再击杀刷新持续时间。

普通敌人 60% 掉落装备，Boss 必掉 Epic。Common / Rare / Epic 及物品等级影响装备属性。基础技能数值来自技能资源；伤害由技能、全部装备属性和事件触发的增益共同决定。Basic 由攻击速度控制攻击间隔；Power 使用固定 CD。冷却绑定槽位，换装不会绕过冷却。换生命装备不会治疗，避免反复换装刷血。

## 结构

| 位置 | 职责 |
| --- | --- |
| `data/abilities/*.tres` | 六种独立技能定义 |
| `data/items/*.tres` | 十二种装备模板，引用技能资源 |
| `data/ashen_garden.tres` | 波次、远程怪比例、Boss 波次和强度成长 |
| `scripts/data/` | Resource 类型、装备实例和目录 |
| `scripts/actors/` | 角色属性、移动、伤害；近战/远程/Boss AI |
| `scripts/systems/ability_system.gd` | 与具体装备分离的可复用技能执行及冷却 |
| `scripts/systems/combat_events.gd` | 伤害、死亡、换装、技能、通关事件 |
| `scripts/systems/` | 装备管理、品质掉落 |
| `scripts/game.gd` | 关卡生命周期、投射物、拾取及原生 Godot UI |

全部图形由 Godot 绘制，占位角色、地面、掉落光束、技能特效、飘字与 Boss 预警不依赖贴图。

## 验证

首次使用命令行测试前，先让编辑器扫描并注册全局类：

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT" --headless --path . --editor --quit
"$GODOT" --headless --path . --script tests/integration.gd
"$GODOT" --headless --path . --script tests/build_simulation.gd
```

测试应使用独立的用户目录；集成测试会临时写入旧版存档以验证它不会被载入，并在结束时恢复原文件。在受限环境可在上述命令前加 `HOME=/private/tmp/cgame-test-home`。集成测试覆盖换装、卸装、六种技能、双 Basic / 双 Power、冷却、被动事件、减速、投射物、掉落、拾取、三波通关、重开、失败、空装备开局、手动拾取起步和忽略旧存档。Build 模拟显式配置未强化的装备，固定时间步推进真实 AI、投射物和技能，验证近战控场与远程爆发两种组合均能打通第一轮。

本次验证：70 项集成检查通过，两个 Build 均击败全部 28 个敌人通关，主场景运行 900 帧无脚本错误。测试也检查了背包和 HUD 的布局边界。受运行环境限制，图形窗口启动异常退出，未完成人工画面与鼠标手感检查；需在本机 Godot 中进一步试玩。
