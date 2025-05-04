import torch
import torch.nn as nn
import torch.nn.functional as F

class DrinkingGameAgent(nn.Module):
    def __init__(self, hidden_size=128, num_layers=2):
        super().__init__()
        self.lstm = nn.LSTM(input_size=10,
                            hidden_size=hidden_size,
                            num_layers=num_layers,
                            batch_first=True)
        self.head = nn.Linear(hidden_size, 210)

    def forward(self, x, valid_mask):
        """
        x: FloatTensor of shape (batch, 10, 5, 6)
        valid_mask: BoolTensor of shape (batch, 7, 5, 6)
        returns: 
          raw_logits: FloatTensor (batch, 210)
          probs:       FloatTensor (batch, 210)
        """
        # ensure float32 before feeding into LSTM
        x = x.float()
        b = x.size(0)

        # reshape to sequence: (batch, seq_len=30, features=10)
        seq = x.view(b, 10, -1).permute(0, 2, 1)

        # LSTM encode
        _, (hn, _) = self.lstm(seq)
        feats = hn[-1]

        # project to 210 logits
        raw = self.head(feats)

        # mask out illegal moves
        valid = valid_mask.view(b, -1)
        masked = raw.masked_fill(~valid, -1e9)

        # softmax to probabilities
        probs = F.softmax(masked, dim=1)
        return raw, probs


if __name__ == "__main__":
    import torch
    dummy_x    = torch.randn(2, 10, 5, 6)
    dummy_mask = torch.ones(2, 7, 5, 6, dtype=torch.bool)
    model      = DrinkingGameAgent()
    raw, probs = model(dummy_x, dummy_mask)
    print(raw.shape, probs.shape)
