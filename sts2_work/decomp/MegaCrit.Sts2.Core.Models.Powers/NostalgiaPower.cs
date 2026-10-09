using System.Linq;
using System.Threading.Tasks;
using MegaCrit.Sts2.Core.Combat;
using MegaCrit.Sts2.Core.Combat.History.Entries;
using MegaCrit.Sts2.Core.Entities.Cards;
using MegaCrit.Sts2.Core.Entities.Powers;

namespace MegaCrit.Sts2.Core.Models.Powers;

public sealed class NostalgiaPower : PowerModel
{
	public override PowerType Type => PowerType.Buff;

	public override PowerStackType StackType => PowerStackType.Counter;

	public override (PileType, CardPilePosition) ModifyCardPlayResultPileTypeAndPosition(CardModel card, bool isAutoPlay, ResourceInfo resources, PileType pileType, CardPilePosition position)
	{
		if (card.Owner.Creature != Owner)
		{
			return (pileType, position);
		}
		CardType type = card.Type;
		if ((uint)(type - 1) > 1u)
		{
			return (pileType, position);
		}
		if (pileType != PileType.Discard)
		{
			return (pileType, position);
		}
		int num = CombatManager.Instance.History.CardPlaysStarted.Count((CardPlayStartedEntry e) =>
		{
			bool flag = e.HappenedThisTurn(CombatState);
			bool flag2 = flag;
			if (flag2)
			{
				CardType type2 = e.CardPlay.Card.Type;
				bool flag3 = (uint)(type2 - 1) <= 1u;
				flag2 = flag3;
			}
			return flag2 && e.CardPlay.Card.Owner == Owner.Player;
		});
		if (num >= Amount)
		{
			return (pileType, position);
		}
		return (PileType.Draw, CardPilePosition.Top);
	}

	public override Task AfterModifyingCardPlayResultPileOrPosition(CardModel card, PileType pileType, CardPilePosition position)
	{
		if (card.Owner.Creature != Owner)
		{
			return Task.CompletedTask;
		}
		Flash();
		return Task.CompletedTask;
	}
}
