# Interimittent FontMergerTestFailure
Yes, I see the failure. The mergesBoldTrait test is failing because FontMerger is attempting to merge all symbolic traits from the existing font into the base font.

When the existing font is a system font (like NSFont.boldSystemFont), its symbolicTraits often contain internal system flags (which explains the high raw value 2147483648 in your error message). When these internal flags are applied to a named font family like "Helvetica" via withSymbolicTraits, the resulting descriptor becomes invalid for that family, causing NSFont(descriptor:size:) to return nil.

Because it returns nil, the code falls back to the defaultFont (which is regular "Helvetica"), and thus the .bold trait is lost.

To fix this, FontMerger should only preserve the specific traits we care about across different font families—typically .bold and .italic.
