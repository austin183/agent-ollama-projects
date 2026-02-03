Critical Issue Found                                                                        
                                                                                              
  The focused_duplicates.py script has a bug. Looking at the output, I can see many groups    
  with mixed decisions that should have been filtered out:                                    
                                                                                              
  Examples of mixed groups incorrectly retained:                                              
  Group ID: 3856                                                                              
  Entries: /Users/projectUser/Pictures/Pictures/Bacup.../DSCK0022.JPG (ARCHIVE) +                  
    /Users/projectUser/Pictures/Pictures/Friends/Myalee/DSCK0022.JPG (KEEP)                        
  ────────────────────────────────────────                                                    
  Group ID: 3858                                                                              
  Entries: Similar mix of ARCHIVE and KEEP entries                                            
  ────────────────────────────────────────                                                    
  Group ID: 3860, 3861, 3862, 3863, 3864, 4664, 5131, 5133                                    
  Entries: Same issue                                                                         
  ---                                                                                         
  The Logic Flaw: The script keeps single-entry groups and groups with mixed decisions, but   
  the output shows mixed decisions being retained. The filter isn't working correctly.        
                                                                                              
  Current Statistics:                                                                         
                                                                                              
  - 5524 total groups analyzed                                                                
  - 613 entries from "fully consistent groups" (but this is incorrect - should be much lower) 
  - ~4911 entries were mixed groups that should have been excluded      