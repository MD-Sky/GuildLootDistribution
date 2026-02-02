local _, NS = ...

NS.CLASS_DATA = {
  WARRIOR = {
    armor = "Plate",
    weapons = { "Swords", "Axes", "Maces", "Shields" },
    specs = {
      Arms = {
        role = "DPS",
        preferredWeapons = { "Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace" },
      },
      Fury = {
        role = "DPS",
        preferredWeapons = { "Dual-Wield Two-Handed" },
      },
      Protection = {
        role = "Tank",
        preferredWeapons = { "One-Handed Sword", "One-Handed Axe", "One-Handed Mace", "Shield" },
      },
    },
  },
  PALADIN = {
    armor = "Plate",
    weapons = { "Two-Handed", "Swords", "Maces", "Shields" },
    specs = {
      Holy = {
        role = "Healer",
        preferredWeapons = { "One-Handed Sword", "One-Handed Mace", "Shield" },
      },
      Protection = {
        role = "Tank",
        preferredWeapons = { "One-Handed Sword", "One-Handed Mace", "Shield" },
      },
      Retribution = {
        role = "DPS",
        preferredWeapons = { "Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace" },
      },
    },
  },
  DEATHKNIGHT = {
    armor = "Plate",
    weapons = { "Swords", "Axes", "Maces" },
    specs = {
      Blood = {
        role = "Tank",
        preferredWeapons = { "Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace" },
      },
      Frost = {
        role = "DPS",
        preferredWeapons = { "Dual-Wield One-Handed", "Two-Handed" },
      },
      Unholy = {
        role = "DPS",
        preferredWeapons = { "Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace" },
      },
    },
  },
  HUNTER = {
    armor = "Mail",
    weapons = { "Bows", "Guns", "Crossbows", "Polearms" },
    specs = {
      ["Beast Mastery"] = {
        role = "DPS",
        preferredWeapons = { "Bow", "Gun", "Crossbow" },
      },
      Marksmanship = {
        role = "DPS",
        preferredWeapons = { "Bow", "Gun", "Crossbow" },
      },
      Survival = {
        role = "DPS",
        preferredWeapons = { "Polearm" },
      },
    },
  },
  SHAMAN = {
    armor = "Mail",
    weapons = { "Maces", "Axes", "Staves", "Shields" },
    specs = {
      Elemental = {
        role = "DPS",
        preferredWeapons = { "Staff", "One-Handed", "Shield" },
      },
      Enhancement = {
        role = "DPS",
        preferredWeapons = { "Dual-Wield One-Handed Axe", "Dual-Wield One-Handed Mace" },
      },
      Restoration = {
        role = "Healer",
        preferredWeapons = { "One-Handed", "Shield" },
      },
    },
  },
  EVOKER = {
    armor = "Mail",
    weapons = { "Staves", "Daggers", "Swords" },
    specs = {
      Devastation = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Preservation = {
        role = "Healer",
        preferredWeapons = { "Staff" },
      },
      Augmentation = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
    },
  },
  DRUID = {
    armor = "Leather",
    weapons = { "Staves", "Maces", "Daggers", "Polearms" },
    specs = {
      Guardian = {
        role = "Tank",
        preferredWeapons = { "Staff", "Polearm" },
      },
      Feral = {
        role = "DPS",
        preferredWeapons = { "Staff", "Polearm" },
      },
      Balance = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Restoration = {
        role = "Healer",
        preferredWeapons = { "Staff", "One-Handed", "Off-Hand" },
      },
    },
  },
  ROGUE = {
    armor = "Leather",
    weapons = { "Daggers", "Swords", "Maces", "Fist Weapons" },
    specs = {
      Assassination = {
        role = "DPS",
        preferredWeapons = { "Daggers" },
      },
      Outlaw = {
        role = "DPS",
        preferredWeapons = { "One-Handed Sword", "One-Handed Mace" },
      },
      Subtlety = {
        role = "DPS",
        preferredWeapons = { "Daggers" },
      },
    },
  },
  MONK = {
    armor = "Leather",
    weapons = { "Staves", "Fist Weapons", "One-Handed" },
    specs = {
      Brewmaster = {
        role = "Tank",
        preferredWeapons = { "Staff", "Polearm" },
      },
      Mistweaver = {
        role = "Healer",
        preferredWeapons = { "Staff" },
      },
      Windwalker = {
        role = "DPS",
        preferredWeapons = { "Dual-Wield One-Handed", "Staff" },
      },
    },
  },
  DEMONHUNTER = {
    armor = "Leather",
    weapons = { "Warglaives", "Swords", "Axes", "Fist Weapons" },
    specs = {
      Havoc = {
        role = "DPS",
        preferredWeapons = { "Dual-Wield Warglaives", "Dual-Wield One-Handed" },
      },
      Devourer = {
        role = "DPS",
      },
      Vengeance = {
        role = "Tank",
        preferredWeapons = { "Dual-Wield Warglaives", "Dual-Wield One-Handed" },
      },
    },
  },
  MAGE = {
    armor = "Cloth",
    weapons = { "Staves", "Daggers", "Swords", "Wands" },
    specs = {
      Arcane = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Fire = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Frost = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
    },
  },
  PRIEST = {
    armor = "Cloth",
    weapons = { "Staves", "Maces", "Daggers", "Wands" },
    specs = {
      Discipline = {
        role = "Healer",
        preferredWeapons = { "Staff" },
      },
      Holy = {
        role = "Healer",
        preferredWeapons = { "Staff" },
      },
      Shadow = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
    },
  },
  WARLOCK = {
    armor = "Cloth",
    weapons = { "Staves", "Daggers", "Swords", "Wands" },
    specs = {
      Affliction = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Demonology = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
      Destruction = {
        role = "DPS",
        preferredWeapons = { "Staff" },
      },
    },
  },
}
