using System.Collections.Generic;
using System.Threading.Tasks;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Entities.Relics;
using MegaCrit.Sts2.Core.Factories;
using MegaCrit.Sts2.Core.Localization.DynamicVars;

namespace MegaCrit.Sts2.Core.Models.Relics;

public sealed class AlchemicalCoffer : RelicModel
{
	private const string _potionSlotsKey = "PotionSlots";

	public override RelicRarity Rarity => RelicRarity.Ancient;

	public override bool HasUponPickupEffect => true;

	protected override IEnumerable<DynamicVar> CanonicalVars => new _003C_003Ez__ReadOnlySingleElementList<DynamicVar>(new DynamicVar("PotionSlots", 4m));

	public override async Task AfterObtained()
	{
		int originalSlotCount = Owner.MaxPotionCount;
		await PlayerCmd.GainMaxPotionCount(DynamicVars["PotionSlots"].IntValue, Owner);
		List<PotionModel> potions = PotionFactory.CreateRandomPotionsOutOfCombat(Owner, DynamicVars["PotionSlots"].IntValue, Owner.RunState.Rng.CombatPotionGeneration);
		for (int i = 0; i < potions.Count; i++)
		{
			await PotionCmd.TryToProcure(potions[i].ToMutable(), Owner, originalSlotCount + i);
		}
	}
}
