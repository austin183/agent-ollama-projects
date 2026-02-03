 DupeRemoval Archival Script Plan                                                             
                                                                                              
 Current Status                                                                               
 Script: analyze_duplicates.py                                                                
 Status: ✓ Complete                                                                           
 Output: Generated DuplicateAnalysis.csv                                                      
 ────────────────────────────────────────                                                     
 Script: focused_duplicates.py                                                                
 Status: ✓ Complete                                                                           
 Output: Generated FocusedDuplicates.csv (590 entries from 5,524 groups)                      
 User Decision                                                                                
                                                                                              
 - Folder cleanup: No - keep redundant folder paths as-is                                     
 - Path normalization: No - preserve original folder structure including duplicates           
                                                                                              
 Task: Create Archival Script                                                                 
                                                                                              
 Create scripts/archive_files.py that:                                                        
 1. Reads FocusedDuplicates.csv                                                               
 2. Filters for Decision == "ARCHIVE"                                                         
 3. Creates Archive directory at workspace/Archive/                                           
 4. Moves files from ARCHIVE locations to Archive with same folder structure                  
 5. Adds comments to each mv command with Group ID and rationale                              
 6. Provides dry-run summary before execution                                                 
                                                                                              
 Files to Create                                                                              
                                                                                              
 - New: scripts/archive_files.py                                                              
                                                                                              
 Expected Output                                                                              
                                                                                              
 Example output lines:                                                                        
 # Group 0: /Users/projectUser/Pictures/Pictures/Bacup 20080426/Other/Other Pics -> Archive        
 mkdir -p /Users/projectUser/workspace/_scratch/DupeRemoval/workspace/Archive/Users/projectUser/Picture 
 s/Pictures/Bacup\ 20080426/Other/Other\Pics                                                  
 mv /Users/projectUser/Pictures/Pictures/Bacup\ 20080426/Other/Other\ Pics/007\ Paper.tiff         
 /Users/projectUser/workspace/_scratch/DupeRemoval/workspace/Archive/Users/projectUser/Pictures/Picture 
 s/Bacup\ 20080426/Other/Other\Pics/007\ Paper.tiff                                           
                                                                                              
 Verification Steps                                                                           
                                                                                              
 1. Run script to generate bash archival commands                                             
 2. Review the output for any unexpected paths                                                
 3. Confirm the script looks correct                                                          
 4. Execute with confirmation prompts 