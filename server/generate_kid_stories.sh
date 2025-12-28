#!/bin/bash

# Generate remaining 10 kid-friendly traditional Bible stories using Gemma-7B
# Stories 7-16

cd /Volumes/T9-AI/bible_pal/assets/stories

# Story 7: The Exodus (Weary, 15 min)
echo "Generating story 7/16: The Exodus..."
ollama run gemma:7b "Write a 15-minute kid-friendly traditional Bible story retelling of the Exodus (Moses leading Israel out of Egypt). The story should have a weary/comforting mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about God's guidance through hard journeys, finding rest, and trusting God's provision. Include the title 'The Exodus: Journey to Rest' at the beginning. Write approximately 1800-2200 words for a 15-minute read." > parable_056_weary_15min_kid_trad.txt

# Story 8: The Creation (Weary, 20 min)
echo "Generating story 8/16: The Creation..."
ollama run gemma:7b "Write a 20-minute kid-friendly traditional Bible story retelling of God's Creation and the seventh day of rest (Genesis 1-2). The story should have a weary/comforting mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about God's gift of rest, Sabbath rest, and that rest is holy. Include the title 'The Creation: God's Good Rest' at the beginning. Write approximately 2400-3000 words for a 20-minute read." > parable_057_weary_20min_kid_trad.txt

# Story 9: Daniel and the Lions (Anxious, 5 min)
echo "Generating story 9/16: Daniel and the Lions..."
ollama run gemma:7b "Write a 5-minute kid-friendly traditional Bible story retelling of Daniel in the lions' den. The story should have an anxious/reassuring mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about trusting God when afraid, God's protection, and courage. Include the title 'Daniel and the Lions' at the beginning. Write approximately 600-750 words for a 5-minute read." > parable_058_anxious_5min_kid_trad.txt

# Story 10: Peter Walks on Water (Anxious, 10 min)
echo "Generating story 10/16: Peter Walks on Water..."
ollama run gemma:7b "Write a 10-minute kid-friendly traditional Bible story retelling of Peter walking on water (Matthew 14). The story should have an anxious/reassuring mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about keeping eyes on Jesus when afraid, trusting when things seem impossible, and that Jesus catches us when we fall. Include the title 'Peter Walks on Water' at the beginning. Write approximately 1200-1500 words for a 10-minute read." > parable_059_anxious_10min_kid_trad.txt

# Story 11: Joshua and Jericho (Anxious, 15 min)
echo "Generating story 11/16: Joshua and the Walls of Jericho..."
ollama run gemma:7b "Write a 15-minute kid-friendly traditional Bible story retelling of Joshua and the Battle of Jericho (Joshua 6). The story should have an anxious/reassuring mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about trusting God with impossible situations, obedience, and that God makes walls fall down. Include the title 'Joshua and the Walls of Jericho' at the beginning. Write approximately 1800-2200 words for a 15-minute read." > parable_060_anxious_15min_kid_trad.txt

# Story 12: Moses and Red Sea (Anxious, 20 min)
echo "Generating story 12/16: Moses and the Red Sea..."
ollama run gemma:7b "Write a 20-minute kid-friendly traditional Bible story retelling of Moses parting the Red Sea (Exodus 14). The story should have an anxious/reassuring mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about God making a way when there seems to be no way, trusting when trapped, and God's power over fear. Include the title 'Moses and the Red Sea' at the beginning. Write approximately 2400-3000 words for a 20-minute read." > parable_061_anxious_20min_kid_trad.txt

# Story 13: Jesus Heals (Hurting, 5 min)
echo "Generating story 13/16: Jesus Heals the Sick..."
ollama run gemma:7b "Write a 5-minute kid-friendly traditional Bible story retelling of Jesus healing sick people (multiple healing stories combined). The story should have a hurting/compassionate mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about Jesus caring when we hurt, healing broken hearts, and coming to Jesus with our pain. Include the title 'Jesus Heals the Sick' at the beginning. Write approximately 600-750 words for a 5-minute read." > parable_062_hurting_5min_kid_trad.txt

# Story 14: Prodigal Son (Hurting, 10 min)
echo "Generating story 14/16: The Prodigal Son..."
ollama run gemma:7b "Write a 10-minute kid-friendly traditional Bible story retelling of the Prodigal Son (Luke 15). The story should have a hurting/compassionate mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about coming home when we've made mistakes, God's forgiveness, and that we're never too far from God's love. Include the title 'The Prodigal Son: Coming Home' at the beginning. Write approximately 1200-1500 words for a 10-minute read." > parable_063_hurting_10min_kid_trad.txt

# Story 15: Joseph (Hurting, 15 min)
echo "Generating story 15/16: Joseph..."
ollama run gemma:7b "Write a 15-minute kid-friendly traditional Bible story retelling of Joseph's journey from pit to palace (Genesis 37-50). The story should have a hurting/compassionate mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about God being with us through hard times, forgiveness after betrayal, and that God brings good from bad situations. Include the title 'Joseph: From Pit to Palace' at the beginning. Write approximately 1800-2200 words for a 15-minute read." > parable_064_hurting_15min_kid_trad.txt

# Story 16: Job (Hurting, 20 min)
echo "Generating story 16/16: Job..."
ollama run gemma:7b "Write a 20-minute kid-friendly traditional Bible story retelling of Job's suffering and restoration (Book of Job). The story should have a hurting/compassionate mood, appropriate for children, non-denominational, and use poetic gentle storytelling. Use only public domain Bible translations (KJV, WEB, ASV, YLT, or DRA) for any scripture references. The story should teach about hope in suffering, that bad things aren't always our fault, trusting God even when we don't understand, and that God restores. Include the title 'Job: Hope in Suffering' at the beginning. Write approximately 2400-3000 words for a 20-minute read." > parable_065_hurting_20min_kid_trad.txt

echo "All 10 remaining stories generated!"
