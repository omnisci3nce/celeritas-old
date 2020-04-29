#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <stdbool.h>
#include <stdio.h>

int spritewidth = 50;
int spriteheight = 37;
int main()
{
    bool quit = false;
    SDL_Event event;

    SDL_Init(SDL_INIT_VIDEO);
    IMG_Init(IMG_INIT_PNG);

    SDL_Window* window = SDL_CreateWindow("Spritesheets Example",
                                            SDL_WINDOWPOS_UNDEFINED,
                                            SDL_WINDOWPOS_UNDEFINED,
                                            640, 480, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
                                SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    SDL_Surface* image = IMG_Load("assets/run.png");
    SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, image);

    const int RUN_ANIM_FRAMES = 6;
    const int ANIMATION_SPEED = 6;

    int frame = 0;
    int animFrame = 0;

    while (!quit)
    {
        while (SDL_PollEvent(&event) != 0)
        {
            switch (event.type)
            {
                case SDL_QUIT:
                    quit = true;
                    break;
            }
        }
        animFrame = frame/ANIMATION_SPEED;
        printf("Animation Frame: %d\n", animFrame);
        
        //Clear screen
        SDL_SetRenderDrawColor(renderer, 0xFF, 0xFF, 0xFF, 0xFF);
        SDL_RenderClear(renderer);

        // Render current frame
        SDL_Rect srcRect = {  animFrame * spritewidth, 0, spritewidth, spriteheight}; 
        SDL_Rect destRect = {10, 10, spritewidth, spriteheight};
        SDL_RenderCopy(renderer, texture, &srcRect, &destRect);

//        printf("Texture X Coord: %d\n", srcRect.x);
        // update screen
        SDL_RenderPresent(renderer);

        // Go to next frame
        ++frame;

        // Cycle anim
        if(frame/ANIMATION_SPEED >= RUN_ANIM_FRAMES )
        {
            frame = 0;
        }
        
    }

    SDL_DestroyTexture(texture);
    SDL_FreeSurface(image);
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    IMG_Quit();
    SDL_Quit();

    return 0;
}
