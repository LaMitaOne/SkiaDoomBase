# SkiaDoomBase
A 2.5D raycasting engine prototype built with Delphi FMX and Skia4Delphi.
     
SkiaDoomBase v.01 alpha       
    
I recently saw a "Can it run Doom?" video on YouTube. So I thought... can skia4delphi run Doom? :D    
    
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/LaMitaOne/SkiaDoomBase)
    
<img width="781" height="591" alt="photo_2026-07-27_16-09-14" src="https://github.com/user-attachments/assets/31235472-ad24-416c-bf15-1de98c60416b" />
     
So started building the basics, and here it is! It's not a full game, but the core engine foundation is fully functional.    
Sooo, i would say...Yes! It can run Doom :D    
    
🎮 Engine Features

    Classic DDA Raycasting: Renders a 2D grid map into a pseudo-3D environment using the Digital Differential Analyzer algorithm.
    Textured Walls & Distance Shading: Procedurally generated wall textures mapped to walls, with Y-axis shading and distance-based darkening for depth.
    Z-Buffered Sprites: Enemy sprites are correctly projected into the 3D world and occluded by walls using a 1D Z-Buffer.
    Near-Clip Fix: Prevents extreme stuttering, screen-filling, and division-by-zero errors when the player gets too close to an enemy.
    Hit-Scan Combat: Shoot enemies using dynamic screen-space crosshair detection.
    View Modes: Toggle between a First-Person Shooter (FPS) view and an Over-The-Shoulder (OTS) cybernetic avatar view.
    Procedural Assets: No external images needed! Wall textures, enemy sprites, and weapon models are generated purely via Skia canvas primitives.
    Threaded Game Loop: Physics and input are processed in a background thread, while rendering is safely synchronized to the main UI thread for a smooth framerate.

🕹️ Controls   
    
    Key	Action
    W / S / Arrows	Move Forward / Backward
    A / D	Strafe Left / Right
    Mouse/Arrows Turn Left / Right
    LMB	Shoot
    V	Toggle FPS / OTS View Mode
    
🛠️ Technical Details & Requirements
     
This entire engine base is contained within a single Delphi unit file (SkiaDoomBase.pas). 

    Language: Object Pascal (Delphi)
    Framework: FireMonkey (FMX)
    Graphics: Skia4Delphi
    Platform: Windows (Uses Winapi.MMSystem and GetAsyncKeyState for input)
    
     
Using royalty free audios from https://www.pavsmusic.com/free-sound-pack-kits/    
      
A zipped .exe and sample project are included in the repository for immediate testing.    
   
    
🎮 Skia4Delphi Games (each one file, no ext engine):    
   2D Platformer https://github.com/LaMitaOne/Skia_PlatformerGame   
   2D Lemmings/Worms/Portal/Touch hybrid https://github.com/LaMitaOne/SkiaLemmings   
   2D Side-scrolling space shooter https://github.com/LaMitaOne/SkiaStarPatrols   
   2.5D C&C style isometric rts https://github.com/LaMitaOne/Skia-RTS-Game   
   2.5D Isometric cat game https://github.com/LaMitaOne/Skia-A-Cats-Life   
   Tetris clone https://github.com/LaMitaOne/Skiatris        
     
🎮 Game components FMX:    
   MRX Gamepad Core https://github.com/LaMitaOne/MRX-Gamepad-Core       

   
If you want to tip me a coffee.. :)   
    
<p align="center">
  <a href="https://www.paypal.com/donate/?hosted_button_id=RX5KTTMXW497Q">
    <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate with PayPal"/>
  </a>
</p>
        
