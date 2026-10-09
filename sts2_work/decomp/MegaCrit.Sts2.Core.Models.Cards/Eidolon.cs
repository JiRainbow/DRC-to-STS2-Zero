using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using MegaCrit.Sts2.Core.Commands;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Players;
using MegaCrit.Sts2.Core.GameActions.Multiplayer;
using MegaCrit.Sts2.Core.HoverTips;
using MegaCrit.Sts2.Core.Models.Powers;

namespace MegaCrit.Sts2.Core.Models.Cards;

public sealed class Eidolon : CardModel
{
	private const int _intangibleThreshold = 9;

	protected override bool ShouldGlowGoldInternal
	{
		get
		{
			PlayerCombatState? playerCombatState = Owner.PlayerCombatState;
			if (playerCombatState == null)
			{
				return false;
			}
			return playerCombatState.Hand.Cards.Count > 9;
		}
	}

	protected override IEnumerable<IHoverTip> ExtraHoverTips => new _003C_003Ez__ReadOnlyArray<IHoverTip>(new IHoverTip[2]
	{
		HoverTipFactory.FromKeyword(CardKeyword.Exhaust),
		HoverTipFactory.FromPower<IntangiblePower>()
	});

	public Eidolon()
		: base(2, CardType.Skill, CardRarity.Rare, TargetType.Self)
	{
	}

	protected override async Task OnPlay(PlayerChoiceContext choiceContext, CardPlay cardPlay)
	{
		await CreatureCmd.TriggerAnim(Owner.Creature, "Cast", Owner.Character.CastAnimDelay);
		List<CardModel> list = Owner.PlayerCombatState.Hand.Cards.ToList();
		int exhaustedCount = 0;
		foreach (CardModel item in list)
		{
			await CardCmd.Exhaust(choiceContext, item);
			exhaustedCount++;
		}
		if (exhaustedCount >= 9)
		{
			await PowerCmd.Apply<IntangiblePower>(choiceContext, Owner.Creature, 1m, Owner.Creature, this);
		}
	}

	protected override void OnUpgrade()
	{
		EnergyCost.UpgradeBy(-1);
	}
}
