using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Creatures;
using MegaCrit.Sts2.Core.Events;
using MegaCrit.Sts2.Core.Extensions;
using MegaCrit.Sts2.Core.Factories;
using MegaCrit.Sts2.Core.Localization.DynamicVars;
using MegaCrit.Sts2.Core.Models.Encounters;
using MegaCrit.Sts2.Core.Models.Monsters;
using MegaCrit.Sts2.Core.Models.PotionPools;
using MegaCrit.Sts2.Core.Rewards;
using MegaCrit.Sts2.Core.Rooms;

namespace MegaCrit.Sts2.Core.Models.Events;

public sealed class BattlewornDummy : EventModel
{
	private const string _setting1HpKey = "Setting1Hp";

	private const string _setting2HpKey = "Setting2Hp";

	private const string _setting3HpKey = "Setting3Hp";

	public override bool IsShared => true;

	protected override IEnumerable<DynamicVar> CanonicalVars => new _003C_003Ez__ReadOnlyArray<DynamicVar>(new DynamicVar[3]
	{
		new DynamicVar("Setting1Hp", ModelDb.Monster<BattleFriendV1>().MinInitialHp),
		new DynamicVar("Setting2Hp", ModelDb.Monster<BattleFriendV2>().MinInitialHp),
		new DynamicVar("Setting3Hp", ModelDb.Monster<BattleFriendV3>().MinInitialHp)
	});

	protected override IReadOnlyList<EventOption> GenerateInitialOptions()
	{
		int playerCount = Owner?.RunState.Players.Count ?? 1;
		int actIndex = Owner?.RunState.CurrentActIndex ?? 0;
		DynamicVars["Setting1Hp"].BaseValue = Creature.ScaleHpForMultiplayer(ModelDb.Monster<BattleFriendV1>().MinInitialHp, ModelDb.Encounter<BattlewornDummyEventEncounter>(), playerCount, actIndex);
		DynamicVars["Setting2Hp"].BaseValue = Creature.ScaleHpForMultiplayer(ModelDb.Monster<BattleFriendV2>().MinInitialHp, ModelDb.Encounter<BattlewornDummyEventEncounter>(), playerCount, actIndex);
		DynamicVars["Setting3Hp"].BaseValue = Creature.ScaleHpForMultiplayer(ModelDb.Monster<BattleFriendV3>().MinInitialHp, ModelDb.Encounter<BattlewornDummyEventEncounter>(), playerCount, actIndex);
		return new _003C_003Ez__ReadOnlyArray<EventOption>(new EventOption[3]
		{
			new EventOption(this, Setting1, "BATTLEWORN_DUMMY.pages.INITIAL.options.SETTING_1"),
			new EventOption(this, Setting2, "BATTLEWORN_DUMMY.pages.INITIAL.options.SETTING_2"),
			new EventOption(this, Setting3, "BATTLEWORN_DUMMY.pages.INITIAL.options.SETTING_3")
		});
	}

	private Task Setting1()
	{
		StartCombat(BattlewornDummyEventEncounter.DummySetting.Setting1);
		return Task.CompletedTask;
	}

	private Task Setting2()
	{
		StartCombat(BattlewornDummyEventEncounter.DummySetting.Setting2);
		return Task.CompletedTask;
	}

	private Task Setting3()
	{
		StartCombat(BattlewornDummyEventEncounter.DummySetting.Setting3);
		return Task.CompletedTask;
	}

	public override async Task Resume(AbstractRoom room)
	{
		CombatRoom combatRoom = (CombatRoom)room;
		BattlewornDummyEventEncounter battlewornDummyEventEncounter = (BattlewornDummyEventEncounter)combatRoom.Encounter;
		if (battlewornDummyEventEncounter.RanOutOfTime)
		{
			SetEventFinished(L10NLookup("BATTLEWORN_DUMMY.pages.DEFEAT.description"));
			return;
		}
		SetEventFinished(L10NLookup("BATTLEWORN_DUMMY.pages.VICTORY.description"));
		switch (battlewornDummyEventEncounter.Setting)
		{
		case BattlewornDummyEventEncounter.DummySetting.Setting1:
		{
			IEnumerable<PotionModel> items = Owner.Character.PotionPool.GetUnlockedPotions(Owner.UnlockState).Concat(ModelDb.PotionPool<SharedPotionPool>().GetUnlockedPotions(Owner.UnlockState));
			PotionModel potionModel = Owner.PlayerRng.Rewards.NextItem(items);
			if (potionModel != null)
			{
				await RewardsCmd.OfferCustom(Owner, new List<Reward>(1)
				{
					new PotionReward(potionModel.ToMutable(), Owner)
				});
			}
			break;
		}
		case BattlewornDummyEventEncounter.DummySetting.Setting2:
		{
			IEnumerable<CardModel> enumerable = PileType.Deck.GetPile(Owner).Cards.Where((CardModel c) => c?.IsUpgradable ?? false).ToList().StableShuffle(Rng)
				.Take(2);
			{
				foreach (CardModel item in enumerable)
				{
					CardCmd.Upgrade(item);
				}
				break;
			}
		}
		case BattlewornDummyEventEncounter.DummySetting.Setting3:
		{
			RelicModel relic = RelicFactory.PullNextRelicFromFront(Owner).ToMutable();
			await RelicCmd.Obtain(relic, Owner);
			break;
		}
		default:
			throw new InvalidOperationException("Setting must be set!");
		}
	}

	private void StartCombat(BattlewornDummyEventEncounter.DummySetting setting)
	{
		BattlewornDummyEventEncounter battlewornDummyEventEncounter = (BattlewornDummyEventEncounter)ModelDb.Encounter<BattlewornDummyEventEncounter>().ToMutable();
		battlewornDummyEventEncounter.Setting = setting;
		EnterCombatWithoutExitingEvent(battlewornDummyEventEncounter, Array.Empty<Reward>(), shouldResumeAfterCombat: true);
	}
}
