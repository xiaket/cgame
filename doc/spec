# 2D Loot ARPG — MVP Specification

**Engine:** Godot 4.x  
**Language:** GDScript  
**Platform:** macOS
**Genre:** Single-player, top-down 2D ARPG

## 1. Game Overview

开发一款以《Diablo》装备系统和《Crashlands》操作方式为参考的 2D ARPG。

核心玩法循环：

**战斗 → 装备掉落 → 更换装备 → 调整 Build → 挑战更强敌人**

设计目标：
- 操作简单，强调清怪爽快感。
- 装备决定角色的战斗能力和技能。
- 不同装备组合产生不同的战斗方式。
- 装备升级能够带来明显的成长反馈。

## 2. Character & Equipment

角色拥有四个装备槽：

| 装备槽 | 技能类型 |
|---|---|
| Weapon | Active |
| Offhand | Active |
| Helmet | Passive |
| Necklace | Passive |

每件装备提供基础属性和一个技能。

装备决定角色的全部技能，卸下装备即失去对应技能。

角色拥有基础生命值、移动速度等属性，通过装备进一步增强。

## 3. Skill System

### Active Skills

分为两类：

- **Basic Attack**：无 CD，可持续攻击。
- **Power Skill**：有 CD，通常具有较高伤害、AOE 或特殊效果。

两个主动技能槽完全对等，允许任意组合：

- Basic + Basic
- Basic + Power
- Power + Power

不限制双 Power 的使用。两个技能均处于 CD 时，角色无法攻击。

### Passive Skills

被动技能自动生效，可以：
- 修改角色属性。
- 增强主动技能。
- 响应战斗事件并触发效果。

### MVP Skill Set

实现以下示例技能：

| 类型 | 技能 | 效果 |
|---|---|---|
| Basic | Slash | 近战单体攻击 |
| Basic | Cleave | 近战范围攻击 |
| Power | Fireball | 远程爆炸伤害，带 CD |
| Power | Frost Nova | 周围 AOE 减速，带 CD |
| Passive | Toughness | 增加生命值 |
| Passive | Bloodlust | 击杀敌人后短暂增加攻击力 |

技能定义与装备数据分离，使用可复用的 Ability System 执行。

## 4. Combat

支持：
- 角色移动、两种主动技能输入。
- 近战、远程和 AOE 攻击。
- 生命值、伤害、攻击速度和 CD。
- 敌人 AI、受伤和死亡。
- 状态效果及战斗事件。

战斗偏向 Diablo-style Hack & Slash，强调走位和技能搭配，而不是复杂连招。

## 5. Equipment & Loot

装备包含：
- 装备槽位。
- 基础属性。
- 一个主动或被动技能。
- 装备品质和数值差异。

怪物死亡后有概率掉落装备。

玩家可以拾取、查看、装备和替换物品。

不同装备可以提供不同技能，换装后立即生效。

## 6. Level

实现一个可重复游玩的测试关卡，包含：

- 普通近战敌人。
- 远程敌人。
- 一个精英或 Boss。
- 怪物掉落装备。
- 明确的关卡完成条件。

通过敌人强度和装备掉落，验证玩家的战斗能力成长。

## 7. Technical Requirements

采用 Data-driven Architecture。

核心模块：

| Module | Responsibility |
|---|---|
| Character | Movement, Health, Stats |
| Equipment | Slots, Items, Attributes |
| Ability | Active / Passive Skills |
| Combat | Damage, Cooldown, Status Effects |
| Events | Combat Event Dispatch |
| Loot | Equipment Drops |
| Enemy | AI and Combat |
| Level | Level Configuration |

装备和技能数据使用 Godot Resources 定义。

技能执行逻辑独立于具体装备。

使用占位美术资源。

## 8. Acceptance Criteria

MVP 完成时，必须能够：

1. 控制角色移动并使用两个主动技能。
2. 自由组合 Basic 和 Power 技能。
3. 通过装备获得两个主动、两个被动技能。
4. 击杀敌人并获得装备掉落。
5. 拾取和更换装备，立即改变属性和技能。
6. 体验至少两种明显不同的有效 Build。
7. 击败 Boss，完成测试关卡。
8. 重新游玩关卡，继续获取装备。

**MVP Goal：验证装备驱动的战斗与 Build 系统是否足够有趣，并形成完整的可玩循环。**
