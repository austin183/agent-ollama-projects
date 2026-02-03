 Here is Claude's plan:                                                                       
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 Plan: Duplicate Folder Categorization Script                                                 
                                                                                              
 Overview                                                                                     
                                                                                              
 Create a Bash script to analyze workspace/LocalHDDuplicates.csv and produce a CSV report     
 showing which folders should be kept vs. archived for each duplicate group.                  
                                                                                              
 Main Workspace                                                                               
                                                                                              
 - /Users/projectUser/workspace/_scratch/DupeRemoval/workspace                                     
                                                                                              
 Input File                                                                                   
                                                                                              
 - workspace/LocalHDDuplicates.csv - Contains duplicate file entries with columns:            
   - Group ID: Identifies duplicate groups                                                    
   - Filename: File name                                                                      
   - Folder: Full path to file                                                                
   - Size (KB): File size                                                                     
   - Match %: Similarity percentage                                                           
                                                                                              
 Output File                                                                                  
                                                                                              
 - workspace/DuplicateAnalysis.csv - Contains per-duplicate-group analysis with:              
   - Group ID                                                                                 
   - List of all folders involved in duplicates                                               
   - Keep/Archive decision for each folder                                                    
   - Rationale                                                                                
                                                                                              
 Implementation Plan                                                                          
                                                                                              
 Step 1: Create Analysis Script                                                               
                                                                                              
 Create scripts/analyze_duplicates.sh:                                                        
                                                                                              
 1. Read CSV: Parse all rows from LocalHDDuplicates.csv                                       
 2. Group by Group ID: Aggregate all unique folder paths per duplicate group                  
 3. Identify Folder Types:                                                                    
   - Determine if folder appears to be "main" source (e.g., Pictures, Music, Documents,       
 Photos)                                                                                      
   - Determine if folder appears to be "backup" source (e.g., PhoneCopy, ExternalBackup,      
 Archive, Temp)                                                                               
 4. Make Decisions:                                                                           
   - If one folder is main source → mark as KEEP                                              
   - If all folders are backup → mark as ARCHIVE (requires manual review)                     
   - If mixed main/backup → mark main as KEEP, backups as ARCHIVE                             
 5. Output CSV: Write results to DuplicateAnalysis.csv                                        
                                                                                              
 Step 2: Script Key Functions (Bash)                                                          
                                                                                              
 categorize_folder() {                                                                        
     local folder="$1"                                                                        
     # Patterns to identify main sources                                                      
     local main_patterns=("Pictures" "Photos" "Documents" "Music" "Videos" "Home" "Desktop"   
 "Downloads" "Movies")                                                                        
     # Patterns to identify backup locations                                                  
     local backup_patterns=("PhoneCopy" "ExternalBackup" "Archive" "Temp" "Backups")          
                                                                                              
     # Check against patterns and return KEEP or ARCHIVE                                      
     ...                                                                                      
 }                                                                                            
                                                                                              
 analyze_duplicate_groups() {                                                                 
     # Main function using awk or bash arrays                                                 
     # Group by Group ID, aggregate folders, categorize, output CSV                           
     ...                                                                                      
 }                                                                                            
                                                                                              
 Step 3: Folder Categorization Rules                                                          
                                                                                              
 Keep folders (main sources):                                                                 
 - Pictures, Photos, Documents, Music, Videos, Movies, Home, Desktop, Downloads               
                                                                                              
 Archive folders (backups/secondary sources):                                                 
 - PhoneCopy, ExternalBackup, Archive, Temp, Backups                                          
                                                                                              
 Mixed/Unknown folders:                                                                       
 - If folder name contains known backup pattern → Archive                                     
 - If folder name contains known main pattern → Keep                                          
 - Otherwise → Require manual review flag                                                     
                                                                                              
 Critical Files                                                                               
                                                                                              
 - workspace/LocalHDDuplicates.csv (input)                                                    
 - scripts/analyze_duplicates.sh (new script)                                                 
 - workspace/DuplicateAnalysis.csv (output report)                                            
                                                                                              
 Verification Steps                                                                           
                                                                                              
 1. Run: bash scripts/analyze_duplicates.sh                                                   
 2. Verify output file exists at workspace/DuplicateAnalysis.csv                              
 3. Review DuplicateAnalysis.csv for accuracy of keep/archive decisions                       
 4. Check that all duplicate groups are represented                                           
                                                                                              
 Next Phase                                                                                   
                                                                                              
 Once the report is reviewed and approved, create a second script to:                         
 - Read DuplicateAnalysis.csv                                                                 
 - Execute mv commands to move archive folders to an archive directory                        
 - Generate a log of moved files for verification                                             
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌